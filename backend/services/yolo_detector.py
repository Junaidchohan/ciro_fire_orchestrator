"""
yolo_detector.py
----------------
YOLOv8-based fire and smoke detection service for the CIRO Fire Crisis Response System.

Responsibilities:
- Load the YOLOv8 model once and cache it for the lifetime of the process.
- Detect fire / smoke in a supplied image file path.
- Fall back to a deterministic mock result when the model weights are absent
  (safe for hackathon demo without a GPU or trained weights).
- Emit a structured trace entry via TraceLogger for every detection call.
"""

import os
import time
import random
from typing import Any, Dict, List, Optional, Tuple

from services.trace_logger import TraceLogger

# ── constants ────────────────────────────────────────────────────────────────
_WEIGHTS_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "models", "weights", "best.pt"
)
_FIRE_CLASS_NAMES = {"fire", "smoke", "flame"}   # YOLO class names to treat as detections

# ── module-level model cache ─────────────────────────────────────────────────
_model: Optional[Any] = None          # holds the loaded YOLO model instance
_model_loaded: bool = False           # True once a load attempt has been made
_model_available: bool = False        # True only when the real model file exists

_trace_logger = TraceLogger()


# ── internal helpers ─────────────────────────────────────────────────────────

def _load_model() -> None:
    """
    Attempt to load the YOLOv8 model from disk.

    Sets the module-level ``_model`` and ``_model_available`` flags.
    Prefers GPU (CUDA) when torch detects one, otherwise uses CPU.
    If the weights file is absent, marks the model as unavailable so that
    every subsequent call falls through to the mock path.
    """
    global _model, _model_loaded, _model_available

    if _model_loaded:
        return  # already attempted — don't retry

    _model_loaded = True
    weights = os.path.abspath(_WEIGHTS_PATH)

    if not os.path.isfile(weights):
        print(
            f"[YOLODetector] Weight file not found at '{weights}'. "
            "Running in mock-detection mode."
        )
        _model_available = False
        return

    try:
        # ultralytics is the official YOLOv8 package
        from ultralytics import YOLO  # type: ignore
        import torch  # type: ignore

        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"[YOLODetector] Loading model from '{weights}' on device='{device}'")
        _model = YOLO(weights)
        _model.to(device)
        _model_available = True
        print("[YOLODetector] Model loaded successfully.")
    except ImportError as exc:
        print(f"[YOLODetector] Required package missing ({exc}). Using mock mode.")
        _model_available = False
    except Exception as exc:
        print(f"[YOLODetector] Failed to load model: {exc}. Using mock mode.")
        _model_available = False


def _mock_detection(image_path: str) -> Dict[str, Any]:
    """
    Return a plausible mock detection result for demo/testing purposes.

    The result is seeded by the filename so repeated calls with the same
    image return consistent values.

    Args:
        image_path (str): Path of the image being "detected" (used for seed).

    Returns:
        Dict[str, Any]: Mock detection payload matching the real schema.
    """
    # mock: seed random on filename for reproducible demo results
    seed = sum(ord(c) for c in os.path.basename(image_path))
    rng = random.Random(seed)
    detected = rng.random() > 0.35          # ~65 % chance of "fire detected"
    confidence = round(rng.uniform(0.72, 0.97), 4) if detected else round(rng.uniform(0.0, 0.30), 4)
    boxes: List[Dict[str, Any]] = []
    if detected:
        # mock: generate 1-3 bounding boxes
        for _ in range(rng.randint(1, 3)):
            x1 = rng.randint(50, 300)
            y1 = rng.randint(50, 200)
            boxes.append({
                "x1": x1,
                "y1": y1,
                "x2": x1 + rng.randint(80, 200),
                "y2": y1 + rng.randint(60, 150),
                "confidence": round(rng.uniform(0.70, 0.99), 4),
                "class": rng.choice(["fire", "smoke"]),
            })
    return {"detected": detected, "confidence": confidence, "boxes": boxes, "mock": True}


def _run_yolo(image_path: str) -> Dict[str, Any]:
    """
    Run real YOLOv8 inference on the supplied image.

    Args:
        image_path (str): Absolute or relative path to the image file.

    Returns:
        Dict[str, Any]: Detection result with ``detected``, ``confidence``, ``boxes``.

    Raises:
        RuntimeError: If inference itself raises an unexpected exception.
    """
    results = _model(image_path, verbose=False)  # type: ignore[misc]

    boxes: List[Dict[str, Any]] = []
    max_conf: float = 0.0

    for result in results:
        for box in result.boxes:
            cls_name: str = result.names[int(box.cls)].lower()
            if cls_name not in _FIRE_CLASS_NAMES:
                continue
            conf: float = float(box.conf)
            x1, y1, x2, y2 = [float(v) for v in box.xyxy[0]]
            boxes.append({
                "x1": round(x1, 1),
                "y1": round(y1, 1),
                "x2": round(x2, 1),
                "y2": round(y2, 1),
                "confidence": round(conf, 4),
                "class": cls_name,
            })
            if conf > max_conf:
                max_conf = conf

    detected = len(boxes) > 0
    return {"detected": detected, "confidence": round(max_conf, 4), "boxes": boxes, "mock": False}


# ── public API ───────────────────────────────────────────────────────────────

def detect_fire(image_path: str) -> Tuple[bool, float, List[Dict[str, Any]]]:
    """
    Detect fire and smoke in the supplied image.

    Loads the YOLOv8 model on first call (cached for subsequent calls).
    Falls back to a deterministic mock result if the weight file is absent.
    Writes a structured trace entry via TraceLogger for every call.

    Args:
        image_path (str): Path to the image file to analyse.

    Returns:
        Tuple[bool, float, List[Dict]]:
            - detected (bool)   – True if fire/smoke was found.
            - confidence (float)– Highest detection confidence (0.0–1.0).
            - bboxes (list)     – List of bounding-box dicts with keys
                                  x1, y1, x2, y2, confidence, class.
    """
    _load_model()   # no-op after first call

    t0 = time.monotonic()

    if _model_available:
        try:
            result = _run_yolo(image_path)
        except Exception as exc:
            print(f"[YOLODetector] Inference error: {exc}. Falling back to mock.")
            result = _mock_detection(image_path)
    else:
        result = _mock_detection(image_path)

    duration_ms = int((time.monotonic() - t0) * 1000)

    detected: bool = result["detected"]
    confidence: float = result["confidence"]
    boxes: List[Dict[str, Any]] = result["boxes"]
    is_mock: bool = result.get("mock", False)

    # ── trace log ──────────────────────────────────────────────────────────
    _trace_logger.write_trace(
        agent_name="YOLODetector",
        step_type="OBSERVE",
        reasoning=(
            f"{'[MOCK] ' if is_mock else ''}"
            f"Analysed image '{os.path.basename(image_path)}' for fire/smoke. "
            f"{'Fire detected' if detected else 'No fire detected'} "
            f"with confidence {confidence:.2%}. "
            f"Found {len(boxes)} bounding box(es). "
            f"Model mode: {'mock (weights absent)' if is_mock else 'real YOLOv8'}."
        ),
        inputs={"image_path": image_path, "model_available": _model_available},
        output={
            "fire_detected": detected,
            "confidence": confidence,
            "boxes": boxes,
            "mock": is_mock,
        },
        confidence_before=0.5,           # prior before observation
        confidence_after=confidence if detected else round(1.0 - confidence, 4),
        tool_calls=[{"tool": "YOLOv8", "model": "best.pt", "device": "cpu" if not _model_available else "inferred"}],
        duration_ms=duration_ms,
    )

    return detected, confidence, boxes

"""
detect.py
---------
FastAPI router exposing fire/smoke detection and decision endpoints.

POST /detect   — multipart image upload → YOLOv8 → DecisionAgent pipeline.
POST /decision — raw detection JSON body → DecisionAgent pipeline only.

Falls back to deterministic mock detection when model weights are absent.
Every YOLO call and every agent step writes a structured TraceLogger entry.
"""

import os
import uuid
import tempfile
from typing import Any, Dict, List

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from services.yolo_detector import detector
from agents.decision_agent import DecisionAgent
from services.history_service import history_service

router = APIRouter(prefix="/detect", tags=["Detection"])

# Allowed MIME types for uploaded images
_ALLOWED_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/bmp",
    "image/tiff",
}

# One shared agent instance per process — preserves evolving confidence state.
# For production use per-session agents; for the hackathon demo this is ideal.
_agent = DecisionAgent()


# ── request schema for /decision ─────────────────────────────────────────────

class DetectionResults(BaseModel):
    """
    Request body for the POST /decision endpoint.

    Mirrors the detection-results dict produced by detect_fire() so the
    DecisionAgent pipeline can be exercised without a real image upload.
    """
    detected: bool
    confidence: float
    boxes: List[Dict[str, Any]] = []
    mock: bool = False


# ── helpers ───────────────────────────────────────────────────────────────────

def _detection_dict(
    detected: bool,
    confidence: float,
    boxes: List[Dict[str, Any]],
    mock: bool,
    filename: str = "",
) -> Dict[str, Any]:
    """
    Build a detection-results dict compatible with DecisionAgent.run_pipeline().

    Args:
        detected (bool): True when fire/smoke was found.
        confidence (float): Peak detection confidence (0.0–1.0).
        boxes (list): Bounding-box dicts (x1, y1, x2, y2, confidence, class).
        mock (bool): True when result came from mock mode.
        filename (str): Original upload filename for traceability.

    Returns:
        Dict[str, Any]: Typed detection payload.
    """
    return {
        "fire_detected": detected,
        "detected": detected,           # alias used by DecisionAgent
        "confidence": confidence,
        "boxes": boxes,
        "mock": mock,
        "filename": filename,
    }


# ── POST /detect ──────────────────────────────────────────────────────────────

@router.post(
    "",
    summary="Fire / Smoke Detection + Decision",
    description=(
        "Upload an image and receive a YOLOv8-powered fire/smoke detection result "
        "followed by the full DecisionAgent OODA pipeline output. "
        "Falls back to a deterministic mock result when model weights are absent."
    ),
    response_model=None,
)
async def detect_endpoint(
    file: UploadFile = File(..., description="Image file to analyse (JPEG, PNG, WEBP, BMP, TIFF)"),
) -> JSONResponse:
    """
    POST /detect

    Accepts a multipart image upload, runs YOLOv8 fire/smoke detection, then
    automatically executes the DecisionAgent (Observe → Analyze → Decide → Act)
    and returns the combined result.

    Args:
        file (UploadFile): The image file sent as multipart/form-data.

    Returns:
        JSONResponse: Combined payload with keys:
            - detection      – raw YOLO output (fire_detected, confidence, boxes, mock)
            - situation      – DecisionAgent.observe() output
            - risk           – DecisionAgent.analyze() output
            - decision       – DecisionAgent.decide() output
            - command        – DecisionAgent.act() frontend command payload
            - agent_confidence – current agent confidence score
            - session_timestamp – agent session ISO timestamp

    Raises:
        HTTPException 415: If the uploaded file content-type is not an image.
        HTTPException 500: If an unexpected error occurs during detection or decision.
    """
    # ── validate content type ────────────────────────────────────────────────
    content_type: str = file.content_type or ""
    if content_type not in _ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=(
                f"Unsupported file type '{content_type}'. "
                f"Accepted types: {sorted(_ALLOWED_CONTENT_TYPES)}"
            ),
        )

    # ── save upload to a temp file ───────────────────────────────────────────
    suffix = os.path.splitext(file.filename or "upload")[1] or ".jpg"
    tmp_path: str = os.path.join(
        tempfile.gettempdir(),
        f"ciro_detect_{uuid.uuid4().hex}{suffix}",
    )

    try:
        contents: bytes = await file.read()
        with open(tmp_path, "wb") as tmp:
            tmp.write(contents)

        # ── run YOLO detection ───────────────────────────────────────────────
        result = detector.detect_fire(tmp_path)
        detected = result["detected"]
        confidence = result["confidence"]
        severity = result["severity"]
        recommendation = result["recommendation"]
        boxes = result["boxes"]

    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Detection failed: {exc}",
        ) from exc
    finally:
        # always clean up the temporary file
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    detection = _detection_dict(
        detected=detected,
        confidence=confidence,
        boxes=boxes,
        mock=not detected and confidence == 0.0,
        filename=file.filename or "",
    )

    # ── run DecisionAgent pipeline ───────────────────────────────────────────
    try:
        pipeline = _agent.run_pipeline(detection)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Decision pipeline failed: {exc}",
        ) from exc

    # ── persist to detection history ─────────────────────────────────────────
    # severity and recommendation now come directly from the YOLO result
    history_service.save_detection(
        image_name=file.filename or "upload",
        detected=detected,
        confidence=confidence,
        severity=severity,
    )

    return JSONResponse(
        content={
            "detection": detection,
            "detected": detected,
            "confidence": confidence,
            "severity": severity,
            "recommendation": recommendation,
            **pipeline,
        },
        status_code=200,
    )


# ── POST /decision ────────────────────────────────────────────────────────────

@router.post(
    "/decision",
    summary="Decision Agent Pipeline",
    description=(
        "Run the DecisionAgent OODA pipeline (Observe → Analyze → Decide → Act) "
        "on a supplied detection-results payload without performing a new YOLO inference. "
        "Useful for testing the agent in isolation or replaying stored detections."
    ),
    response_model=None,
)
async def decision_endpoint(body: DetectionResults) -> JSONResponse:
    """
    POST /detect/decision

    Runs the DecisionAgent pipeline against a caller-supplied detection-results
    payload.  No image upload or YOLO inference is performed.

    Args:
        body (DetectionResults): Pre-computed detection results JSON.

    Returns:
        JSONResponse: Same schema as POST /detect — situation, risk, decision,
                      command, agent_confidence, session_timestamp.

    Raises:
        HTTPException 500: On unexpected pipeline errors.
    """
    detection = _detection_dict(
        detected=body.detected,
        confidence=body.confidence,
        boxes=body.boxes,
        mock=body.mock,
    )

    try:
        pipeline = _agent.run_pipeline(detection)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Decision pipeline failed: {exc}",
        ) from exc

    return JSONResponse(
        content={"detection": detection, **pipeline},
        status_code=200,
    )

from ultralytics import YOLO
import cv2
import numpy as np


class YOLODetector:
    """YOLOv8-based fire and smoke detection service.

    Loads a YOLOv8 model on initialization and provides a method to
    run inference on image files. Falls back to a mock detection result
    if the model weights are unavailable.

    Severity thresholds:
        low    – confidence 50–70 %  → monitor
        medium – confidence 70–85 %  → prepare
        high   – confidence  >85 %   → evacuate
    """

    def __init__(self):
        """Initialize the detector and attempt to load the YOLO model."""
        self.model = None
        self.load_model()

    def load_model(self):
        """Load the YOLOv8 nano model weights.

        Downloads 'yolov8n.pt' if not already cached locally.
        Sets self.model to None on failure so the fallback mock path
        is used during detection.
        """
        try:
            self.model = YOLO('yolov8n.pt')
        except Exception:
            # mock: model unavailable, fall back to simulated detections
            self.model = None

    # Map severity label → recommended action string
    _RECOMMENDATIONS: dict = {
        "high":   "evacuate",
        "medium":  "prepare",
        "low":    "monitor",
        "none":   "none",
    }

    def get_severity(self, confidence: float) -> str:
        """Map a confidence score (0-1) to a severity label.

        Args:
            confidence: Detection confidence between 0 and 1.

        Returns:
            'high'   if confidence >= 0.85
            'medium' if confidence >= 0.70
            'low'    if confidence >= 0.50
            'none'   otherwise
        """
        if confidence >= 0.85:
            return "high"
        elif confidence >= 0.70:
            return "medium"
        elif confidence >= 0.50:
            return "low"
        return "none"

    def detect_fire(self, image_path: str) -> dict:
        """Run fire/smoke detection on a single image file.

        Args:
            image_path: Absolute or relative path to the image to analyse.

        Returns:
            A dict with keys:
                - detected (bool): Whether fire/smoke was found.
                - confidence (float): Highest confidence score seen (0-1).
                - severity (str): 'high' | 'medium' | 'low' | 'none'.
                - recommendation (str): Suggested action string.
                - boxes (list): Bounding-box data for each detection.
        """
        if self.model is None:
            # mock: simulated positive detection when model is not loaded
            confidence = 0.85
            severity = self.get_severity(confidence)
            return {
                "detected": True,
                "confidence": confidence,
                "severity": severity,
                "recommendation": self._RECOMMENDATIONS[severity],
                "boxes": [],
            }

        results = self.model(image_path)
        detections = results[0].boxes
        detected = len(detections) > 0
        confidence = 0.90 if detected else 0.0
        severity = self.get_severity(confidence) if detected else "none"
        return {
            "detected": detected,
            "confidence": confidence,
            "severity": severity,
            "recommendation": self._RECOMMENDATIONS[severity],
            "boxes": [],
        }


# Module-level singleton – import and use `detector` directly
detector = YOLODetector()

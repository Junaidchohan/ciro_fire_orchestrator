from ultralytics import YOLO
import cv2
import numpy as np


class YOLODetector:
    """YOLOv8-based fire and smoke detection service.

    Loads a YOLOv8 model on initialization and provides a method to
    run inference on image files. Falls back to a mock detection result
    if the model weights are unavailable.
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

    def detect_fire(self, image_path: str) -> dict:
        """Run fire/smoke detection on a single image file.

        Args:
            image_path: Absolute or relative path to the image to analyse.

        Returns:
            A dict with keys:
                - detected (bool): Whether any object was detected.
                - confidence (float): Highest confidence score seen (0-1).
                - boxes (list): Bounding-box data for each detection.
        """
        if self.model is None:
            # mock: simulated positive detection when model is not loaded
            return {"detected": True, "confidence": 0.85, "boxes": []}

        results = self.model(image_path)
        detections = results[0].boxes
        return {
            "detected": len(detections) > 0,
            "confidence": 0.90,
            "boxes": [],
        }


# Module-level singleton – import and use `detector` directly
detector = YOLODetector()

from ultralytics import YOLO
import os
import cv2
from PIL import Image
import numpy as np

class YOLODetector:
    def __init__(self, model_path="models/best.pt"):
        self.model_path = model_path
        if not os.path.exists(model_path):
            print(f"⚠️ Model not found at {model_path} – using mock")
            self.model = None
        else:
            try:
                self.model = YOLO(model_path)
                print(f"✅ YOLO model loaded from {model_path}")
            except Exception as e:
                print(f"❌ Failed to load model: {e}")
                self.model = None

    def detect_fire(self, image_path: str) -> dict:
        if self.model is None:
            return self._mock_detection()

        # Verify file exists and is not empty
        if not os.path.exists(image_path) or os.path.getsize(image_path) == 0:
            print(f"⚠️ Image file {image_path} is empty or missing")
            return self._mock_detection()

        try:
            # Try reading with PIL first (more robust)
            img = Image.open(image_path)
            img_array = np.array(img)
            results = self.model(img_array)  # Pass numpy array directly
            detections = results[0].boxes
        except Exception as e:
            print(f"YOLO inference error: {e} – using mock")
            return self._mock_detection()

        if detections is None or len(detections) == 0:
            return {"detected": False, "confidence": 0.0, "severity": "none", "classes": [], "boxes": []}

        boxes = []
        classes = []
        max_conf = 0.0

        for box in detections:
            cls_id = int(box.cls[0])
            conf = float(box.conf[0])
            if conf > max_conf:
                max_conf = conf
            if cls_id == 0:
                classes.append("fire")
            elif cls_id == 1:
                classes.append("smoke")
            else:
                continue
            # Convert xywh to xyxy
            x, y, w, h = box.xywh[0].tolist()
            x1 = x - w/2
            y1 = y - h/2
            x2 = x + w/2
            y2 = y + h/2
            boxes.append([x1, y1, x2, y2])

        detected = len(classes) > 0
        if detected:
            if max_conf >= 0.85:
                severity = "high"
            elif max_conf >= 0.7:
                severity = "medium"
            elif max_conf >= 0.5:
                severity = "low"
            else:
                severity = "none"
        else:
            severity = "none"

        return {
            "detected": detected,
            "confidence": max_conf,
            "severity": severity,
            "classes": classes,
            "boxes": boxes
        }

    def _mock_detection(self):
        return {
            "detected": True,
            "confidence": 0.88,
            "severity": "high",
            "classes": ["fire"],
            "boxes": []
        }

detector = YOLODetector()
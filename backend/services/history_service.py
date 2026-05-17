"""
history_service.py – Persistence layer for fire detection history.

Saves each detection event to logs/detection_history.json at the workspace root.
Each entry stores: id, timestamp, image_name, detected (bool),
                   confidence (float), severity (str).
"""

import json
import os
from datetime import datetime
from typing import Any, Dict, List

# Resolve absolute path so the file is always found regardless of CWD
_BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
_WORKSPACE_ROOT = os.path.abspath(os.path.join(_BACKEND_DIR, "..", ".."))
_HISTORY_FILE = os.path.join(_WORKSPACE_ROOT, "logs", "detection_history.json")


class HistoryService:
    """Manages the JSON-based detection history log."""

    def __init__(self) -> None:
        """Initialises the service, creating the history file if absent."""
        self._ensure_file()

    # ── private helpers ───────────────────────────────────────────────────────

    def _ensure_file(self) -> None:
        """
        Creates the log directory and an empty JSON array file if they
        do not already exist.
        """
        os.makedirs(os.path.dirname(_HISTORY_FILE), exist_ok=True)
        if not os.path.exists(_HISTORY_FILE):
            with open(_HISTORY_FILE, "w", encoding="utf-8") as f:
                json.dump([], f)

    # ── public API ────────────────────────────────────────────────────────────

    def save_detection(
        self,
        image_name: str,
        detected: bool,
        confidence: float,
        severity: str,
    ) -> Dict[str, Any]:
        """
        Prepends a new detection record to the history JSON file.

        Args:
            image_name (str): Original filename of the submitted image.
            detected (bool): Whether fire/smoke was detected.
            confidence (float): Detection confidence score (0.0 – 1.0).
            severity (str): Risk level — 'high', 'medium', 'low', or 'none'.

        Returns:
            Dict[str, Any]: The newly created detection record.
        """
        history = self.load_history(limit=None)  # load all to compute next id
        entry: Dict[str, Any] = {
            "id": len(history) + 1,
            "timestamp": datetime.now().isoformat(),
            "image_name": image_name,
            "detected": detected,
            "confidence": round(float(confidence), 4),
            "severity": severity,
        }
        # Prepend so index 0 is always the latest
        history.insert(0, entry)
        with open(_HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2, ensure_ascii=False)
        return entry

    def load_history(self, limit: int | None = 50) -> List[Dict[str, Any]]:
        """
        Loads detection records from the JSON file.

        Args:
            limit (int | None): Maximum records to return. None returns all.

        Returns:
            List[Dict[str, Any]]: Detection records, newest first.
        """
        try:
            with open(_HISTORY_FILE, "r", encoding="utf-8") as f:
                history: List[Dict[str, Any]] = json.load(f)
        except (json.JSONDecodeError, OSError):
            history = []
        return history if limit is None else history[:limit]


# Module-level singleton – import and use directly
history_service = HistoryService()

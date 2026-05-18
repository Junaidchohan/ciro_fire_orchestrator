"""
crisis_classifier.py
--------------------
Multi-hazard crisis classifier for CIRO Fire Crisis Response System.
Supports fire (via YOLO), flood (weather/social signals), and heatwave
(temperature thresholds) detection. Returns the highest-priority detected
crisis from all classifiers for downstream decision logic.
"""

from typing import Dict, Any, List, Optional
from services.trace_logger import TraceLogger


# Priority order: higher index = higher severity priority
_CRISIS_PRIORITY: Dict[str, int] = {
    "fire": 3,
    "heatwave": 2,
    "flood": 1,
}

# Severity numeric mapping for comparison
_SEVERITY_RANK: Dict[str, int] = {
    "critical": 4,
    "high": 3,
    "medium": 2,
    "low": 1,
    "none": 0,
}


class CrisisClassifier:
    """
    Classifies incoming sensor/social data into crisis types.

    Supported crisis types: fire, flood, heatwave.
    Each classifier returns a typed result dict:
        {
            "detected": bool,
            "confidence": float,          # 0.0 – 1.0
            "severity": str,              # "critical"|"high"|"medium"|"low"|"none"
            "crisis_type": str,
            "reasoning": str,
        }

    The `classify_all` method returns the single highest-priority result.
    """

    def __init__(self) -> None:
        """Initialize classifier with supported crisis types and trace logger."""
        self.crisis_types: List[str] = ["fire", "flood", "heatwave"]
        self.logger = TraceLogger()

    # ── Fire ──────────────────────────────────────────────────────────────────
    def classify_fire(
        self, yolo_result: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Classify fire crisis from YOLO detection output.

        Args:
            yolo_result: Dict from YOLODetector with keys 'detected', 'confidence',
                         and optionally 'severity'.

        Returns:
            Typed crisis result dict.
        """
        detected: bool = yolo_result.get("detected", False)
        confidence: float = float(yolo_result.get("confidence", 0.0))
        yolo_severity: str = yolo_result.get("severity", "none")

        if detected and confidence > 0.7:
            severity = "high" if yolo_severity not in _SEVERITY_RANK else yolo_severity
        elif detected:
            severity = "medium"
        else:
            severity = "none"

        reasoning = (
            f"YOLO fire detection: detected={detected}, "
            f"confidence={confidence:.2f}, yolo_severity={yolo_severity}"
        )
        return {
            "detected": detected,
            "confidence": confidence,
            "severity": severity,
            "crisis_type": "fire",
            "reasoning": reasoning,
        }

    # ── Flood ─────────────────────────────────────────────────────────────────
    def classify_flood(
        self,
        weather_data: Dict[str, Any],
        social_data: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Classify flood crisis from weather sensor and social media signals.

        Args:
            weather_data: Dict containing meteorological metrics, e.g.
                          {"rainfall_mm": 25, "water_level_m": 1.2}.
            social_data: Dict containing social/textual signal, e.g.
                         {"text": "streets flooded near downtown"}.

        Returns:
            Typed crisis result dict.
        """
        rainfall: float = float(weather_data.get("rainfall_mm", 0))
        social_text: str = social_data.get("text", "").lower()
        social_hit: bool = any(kw in social_text for kw in ["flood", "inundation", "overflow", "submerged"])

        if rainfall > 50:
            result = {"detected": True, "confidence": 0.95, "severity": "critical"}
            reasoning = f"Extreme rainfall {rainfall}mm exceeds critical threshold (>50mm)"
        elif rainfall > 20:
            result = {"detected": True, "confidence": 0.85, "severity": "high"}
            reasoning = f"Heavy rainfall {rainfall}mm exceeds high-risk threshold (>20mm)"
        elif rainfall > 10 or social_hit:
            result = {"detected": True, "confidence": 0.70, "severity": "medium"}
            reasoning = (
                f"Moderate rainfall {rainfall}mm or social signal detected "
                f"(keyword_match={social_hit})"
            )
        else:
            result = {"detected": False, "confidence": 0.0, "severity": "none"}
            reasoning = f"No flood indicators: rainfall={rainfall}mm, social_hit={social_hit}"

        return {**result, "crisis_type": "flood", "reasoning": reasoning}

    # ── Heatwave ──────────────────────────────────────────────────────────────
    def classify_heatwave(
        self,
        weather_data: Dict[str, Any],
        social_data: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        Classify heatwave crisis from temperature sensor and social signals.

        Args:
            weather_data: Dict containing temperature metrics, e.g.
                          {"temperature": 43, "humidity": 20}.
            social_data: Dict containing social/textual signal, e.g.
                         {"text": "extreme heat advisory issued"}.

        Returns:
            Typed crisis result dict.
        """
        temp: float = float(weather_data.get("temperature", 0))
        social_text: str = social_data.get("text", "").lower()
        social_hit: bool = any(kw in social_text for kw in ["heatwave", "heat wave", "extreme heat", "heat advisory"])

        if temp > 45:
            result = {"detected": True, "confidence": 0.95, "severity": "critical"}
            reasoning = f"Temperature {temp}°C exceeds critical threshold (>45°C)"
        elif temp > 40:
            result = {"detected": True, "confidence": 0.85, "severity": "high"}
            reasoning = f"Temperature {temp}°C exceeds high-risk threshold (>40°C)"
        elif temp > 38 or social_hit:
            result = {"detected": True, "confidence": 0.70, "severity": "medium"}
            reasoning = (
                f"Elevated temperature {temp}°C or social heat advisory detected "
                f"(keyword_match={social_hit})"
            )
        else:
            result = {"detected": False, "confidence": 0.0, "severity": "none"}
            reasoning = f"No heatwave indicators: temp={temp}°C, social_hit={social_hit}"

        return {**result, "crisis_type": "heatwave", "reasoning": reasoning}

    # ── Aggregator ────────────────────────────────────────────────────────────
    def classify_all(
        self,
        yolo_result: Optional[Dict[str, Any]] = None,
        weather_data: Optional[Dict[str, Any]] = None,
        social_data: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Run all crisis classifiers and return the highest-priority detected crisis.

        Priority logic:
        1. Only considers crises where detected=True.
        2. Breaks ties by severity rank first, then by crisis priority index.
        3. If no crisis detected, returns a safe 'none' response.

        Args:
            yolo_result:  YOLO fire detection output (defaults to empty dict).
            weather_data: Weather sensor payload (defaults to empty dict).
            social_data:  Social signal payload (defaults to empty dict).

        Returns:
            The highest-priority typed crisis result dict, plus an
            'all_results' key with the full classification list.
        """
        yolo_result = yolo_result or {}
        weather_data = weather_data or {}
        social_data = social_data or {}

        fire_result = self.classify_fire(yolo_result)
        flood_result = self.classify_flood(weather_data, social_data)
        heatwave_result = self.classify_heatwave(weather_data, social_data)

        all_results = [fire_result, flood_result, heatwave_result]
        detected_results = [r for r in all_results if r["detected"]]

        self.logger.write_trace(
            agent_name="crisis_classifier",
            step_type="CLASSIFY",
            reasoning=(
                f"Ran all classifiers. Detected: "
                f"{[r['crisis_type'] for r in detected_results] or 'none'}"
            ),
            inputs={"yolo_result": yolo_result, "weather_data": weather_data, "social_data": social_data},
            output={"all_results": all_results},
            confidence_before=0.5,
            confidence_after=0.9 if detected_results else 0.5,
            tool_calls=[],
            duration_ms=2,
        )

        if not detected_results:
            return {
                "detected": False,
                "confidence": 0.0,
                "severity": "none",
                "crisis_type": "none",
                "reasoning": "No crisis indicators found across all classifiers",
                "all_results": all_results,
            }

        # Select highest priority: sort by (severity_rank DESC, crisis_priority DESC)
        best = max(
            detected_results,
            key=lambda r: (
                _SEVERITY_RANK.get(r["severity"], 0),
                _CRISIS_PRIORITY.get(r["crisis_type"], 0),
            ),
        )

        self.logger.write_trace(
            agent_name="crisis_classifier",
            step_type="SELECT",
            reasoning=(
                f"Selected crisis_type={best['crisis_type']} "
                f"(severity={best['severity']}, confidence={best['confidence']:.2f}). "
                f"Reason: {best['reasoning']}"
            ),
            inputs={},
            output={"selected": best},
            confidence_before=0.9,
            confidence_after=best["confidence"],
            tool_calls=[],
            duration_ms=1,
        )

        return {**best, "all_results": all_results}


# Module-level singleton
classifier = CrisisClassifier()

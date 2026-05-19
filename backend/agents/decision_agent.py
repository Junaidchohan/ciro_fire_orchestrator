import time
from typing import Any, Dict, Optional
from services.trace_logger import TraceLogger
from services.resource_allocator import allocator
from agents.crisis_classifier import classifier

_RECOMMENDED_ACTIONS = {
    "evacuate": "Immediate evacuation required – move to safe zone.",
    "warning":  "Warning issued – prepare for possible evacuation.",
    "monitor":  "Continue monitoring – no immediate action needed.",
}


class DecisionAgent:
    def __init__(self):
        self.logger = TraceLogger()
        self.confidence = 0.5

    def decide(
        self,
        detection_result: Dict[str, Any],
        weather_data: Optional[Dict[str, Any]] = None,
        social_data: Optional[Dict[str, Any]] = None,
        fused_signal: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        weather_data = weather_data or {}
        social_data = social_data or {}
        location = detection_result.get("location", "Unknown")

        # Determine crisis type and confidence
        detected = detection_result.get("detected", False)
        confidence = detection_result.get("confidence", 0.0)

        # If no weather/social, fallback to fire detection
        if not weather_data and not social_data:
            crisis_type = "fire"
            severity = detection_result.get("severity", "high" if confidence > 0.8 else "medium")
        else:
            # Use classifier if available
            try:
                classification = classifier.classify_all(
                    yolo_result=detection_result,
                    weather_data=weather_data,
                    social_data=social_data,
                )
                crisis_type = classification.get("crisis_type", "fire")
                severity = classification.get("severity", "medium")
                confidence = classification.get("confidence", confidence)
                detected = classification.get("detected", detected)
            except Exception:
                crisis_type = "fire"
                severity = "high" if confidence > 0.8 else "medium"

        # Decide action
        if detected and confidence >= 0.7:
            action = "evacuate"
            final_confidence = min(confidence + 0.05, 1.0)
            reasoning = f"{crisis_type.capitalize()} detected with high confidence ({confidence:.0%}) → immediate evacuation required."
        elif detected and confidence >= 0.4:
            action = "warning"
            final_confidence = confidence
            reasoning = f"Moderate {crisis_type} signals ({confidence:.0%}) → issue warning."
        else:
            action = "monitor"
            final_confidence = max(confidence, 0.3)
            reasoning = f"No immediate crisis threat ({confidence:.0%}) → continue monitoring."

        recommended_action = _RECOMMENDED_ACTIONS.get(action, "Await further data.")

        # Resource allocation
        try:
            allocation = allocator.allocate(
                crisis_type=crisis_type if crisis_type != "none" else "fire",
                severity=severity,
                location=location,
            )
        except Exception:
            allocation = {"allocated_resources": [], "estimated_arrival_min": "N/A"}

        # Log trace
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="DECIDE",
            reasoning=reasoning,
            inputs={"detection_result": detection_result},
            output={"action": action, "recommended_action": recommended_action},
            confidence_before=self.confidence,
            confidence_after=final_confidence,
            tool_calls=[],
            duration_ms=0,
        )

        return {
            "crisis_type": crisis_type,
            "severity": severity,
            "confidence": final_confidence,
            "action": action,
            "recommendation": recommended_action,
            "reasoning": reasoning,
            "signal_sources": ["image"],
            "allocation": allocation,
        }


agent = DecisionAgent()
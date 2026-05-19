"""
decision_agent.py
-----------------
Decision Agent for CIRO Crisis Response System.

Runs all CrisisClassifier sub-classifiers (fire, flood, heatwave),
selects the highest-priority detected crisis, decides on an action level,
and automatically triggers the ResourceAllocator to dispatch emergency units.

Signal sources:
    - image/YOLO   → fire confidence via yolo_result
    - weather_data → flood + heatwave classifiers
    - social_data  → flood + heatwave social signal boost
"""

import time
from typing import Any, Dict, Optional

from services.trace_logger import TraceLogger
from services.resource_allocator import allocator
from agents.crisis_classifier import classifier


# Recommended human-readable actions keyed by decision action
_RECOMMENDED_ACTIONS: Dict[str, str] = {
    "evacuate": "Initiate immediate evacuation and deploy all emergency units.",
    "warning":  "Issue public warning, pre-position response teams.",
    "monitor":  "Continue passive monitoring; no immediate action required.",
}


class DecisionAgent:
    """
    Processes detection results + weather/social signals via CrisisClassifier,
    selects the dominant crisis, maps it to an action, and orchestrates
    resource allocation.

    Steps:
        OBSERVE  → Read all input signals.
        CLASSIFY → Run CrisisClassifier.classify_all() to find dominant crisis.
        DECIDE   → Map confidence/severity → action.
        ALLOCATE → Call ResourceAllocator with crisis_type + severity.
    """

    def __init__(self) -> None:
        """Initialise the agent with a TraceLogger and baseline confidence."""
        self.logger = TraceLogger()
        self.confidence: float = 0.5

    # ------------------------------------------------------------------
    # Main entry point
    # ------------------------------------------------------------------

    def decide(
        self,
        detection_result: Dict[str, Any],
        weather_data: Optional[Dict[str, Any]] = None,
        social_data: Optional[Dict[str, Any]] = None,
        # Legacy parameter kept for backward-compat; ignored when weather/social given
        fused_signal: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Run all crisis classifiers, select highest-confidence crisis, decide
        on an action, allocate resources, and return a structured response.

        Args:
            detection_result (Dict[str, Any]): Output from YOLODetector / FireAgent.
                Expected keys: 'detected' (bool), 'confidence' (float),
                'severity' (str), 'location' (str, optional).
            weather_data (Dict[str, Any], optional): Weather sensor payload, e.g.
                {"rainfall_mm": 25, "temperature": 42, "flood_risk": True}.
            social_data (Dict[str, Any], optional): Social signal payload, e.g.
                {"text": "flooding reported near river"}.
            fused_signal (Dict[str, Any], optional): Legacy fused signal dict.
                Preserved for backward compatibility; ignored when weather/social given.

        Returns:
            Dict[str, Any]: Decision dict containing:
                - crisis_type        (str):   Detected crisis category.
                - severity           (str):   Severity level of dominant crisis.
                - confidence         (float): Confidence of dominant crisis.
                - action             (str):   'evacuate' | 'warning' | 'monitor'.
                - recommended_action (str):   Human-readable action description.
                - reasoning          (str):   Human-readable justification.
                - signal_sources     (list):  Which signal sources were used.
                - all_classifiers    (list):  Full results from every classifier.
                - allocation         (dict):  ResourceAllocator output.
        """
        _t0 = time.time()

        weather_data = weather_data or {}
        social_data  = social_data  or {}
        location: str = detection_result.get("location", "Unknown Location")

        # ── OBSERVE ───────────────────────────────────────────────────
        signal_sources = ["image"]
        if weather_data:
            signal_sources.append("weather")
        if social_data:
            signal_sources.append("social")

        observe_reasoning = (
            f"Received signals from: {signal_sources}. "
            f"Raw detection: detected={detection_result.get('detected', False)}, "
            f"confidence={detection_result.get('confidence', 0.0):.2f}."
        )
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="OBSERVE",
            reasoning=observe_reasoning,
            inputs={
                "detection_result": detection_result,
                "weather_data": weather_data,
                "social_data": social_data,
            },
            output={},
            confidence_before=self.confidence,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=1,
        )

        # ── CLASSIFY — run all classifiers, pick dominant crisis ──────
        classification = classifier.classify_all(
            yolo_result=detection_result,
            weather_data=weather_data,
            social_data=social_data,
        )

        crisis_type: str  = classification.get("crisis_type", "none")
        severity:    str  = classification.get("severity",    "none")
        confidence:  float = float(classification.get("confidence", 0.0))
        detected:    bool  = classification.get("detected", False)
        all_classifiers    = classification.get("all_results", [])

        classify_reasoning = (
            f"Classifier selected crisis_type='{crisis_type}' "
            f"(severity={severity}, confidence={confidence:.2f}). "
            f"Reasoning: {classification.get('reasoning', '')}"
        )
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="CLASSIFY",
            reasoning=classify_reasoning,
            inputs={"all_results": all_classifiers},
            output={"crisis_type": crisis_type, "severity": severity, "confidence": confidence},
            confidence_before=self.confidence,
            confidence_after=confidence,
            tool_calls=[],
            duration_ms=1,
        )

        # ── DECIDE — map confidence/severity to action ────────────────
        if detected and confidence > 0.7:
            action = "evacuate"
            final_conf = min(confidence + 0.05, 1.0)
            reasoning = (
                f"{crisis_type.capitalize()} detected with high confidence "
                f"({confidence:.2f}) — immediate evacuation required."
            )
        elif detected and confidence >= 0.4:
            action = "warning"
            final_conf = confidence
            reasoning = (
                f"Moderate {crisis_type} signals detected "
                f"({confidence:.2f}) — issuing precautionary warning."
            )
        else:
            action = "monitor"
            final_conf = max(confidence, 0.30)
            reasoning = (
                f"No significant crisis threat detected "
                f"({confidence:.2f}) — continuing passive monitoring."
            )

        recommended_action = _RECOMMENDED_ACTIONS.get(action, "Await further data.")

        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="DECIDE",
            reasoning=reasoning,
            inputs={"confidence": confidence, "detected": detected, "severity": severity},
            output={"action": action, "recommended_action": recommended_action},
            confidence_before=confidence,
            confidence_after=final_conf,
            tool_calls=[],
            duration_ms=1,
        )

        # ── ALLOCATE ─────────────────────────────────────────────────
        # Map action → severity tier for ResourceAllocator
        action_to_severity: Dict[str, str] = {
            "evacuate": "high",
            "warning":  "medium",
            "monitor":  "none",
        }
        alloc_severity = action_to_severity.get(action, severity)

        allocation = allocator.allocate(
            crisis_type=crisis_type if crisis_type != "none" else "fire",
            severity=alloc_severity,
            location=location,
        )

        duration_ms = int((time.time() - _t0) * 1000)
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="ACT",
            reasoning=(
                f"ResourceAllocator dispatched {allocation.get('allocated_resources', [])} "
                f"with ETA={allocation.get('estimated_arrival_min', 'N/A')} min."
            ),
            inputs={"crisis_type": crisis_type, "severity": alloc_severity, "location": location},
            output=allocation,
            confidence_before=final_conf,
            confidence_after=final_conf,
            tool_calls=[],
            duration_ms=duration_ms,
        )

        # ── Compose final output ─────────────────────────────────────
        return {
            "crisis_type":        crisis_type,
            "dominant_crisis":    crisis_type,       # alias for fused-signal API compat
            "severity":           severity,
            "confidence":         final_conf,
            "action":             action,
            "recommended_action": recommended_action,
            "recommendation":     recommended_action,  # alias for UI compat
            "reasoning":          reasoning,
            "signal_sources":     signal_sources,
            "all_classifiers":    all_classifiers,
            "allocation":         allocation,
        }


# Module-level singleton
agent = DecisionAgent()

"""
decision_agent.py
-----------------
Decision Agent for CIRO Crisis Response System.

Observes detection results + optional fused multi-source signals,
decides on an action level, then automatically triggers the
ResourceAllocator to dispatch the appropriate emergency units.

Signal priority when fused_signal is provided:
    - image   weight 0.6 (from YOLODetector confidence)
    - weather weight 0.2 } combined into fused_score by SignalFusion
    - social  weight 0.2 }
"""

import time
from typing import Any, Dict, Optional

from services.trace_logger import TraceLogger
from services.resource_allocator import allocator


class DecisionAgent:
    """
    Processes fire/crisis detection results (and optional fused signals)
    and orchestrates resource allocation as a single, integrated decision cycle.

    Steps:
        OBSERVE  → Read detection confidence, fused score, and crisis_type.
        DECIDE   → Blend image + fused scores → action ('evacuate'|'warning'|'monitor').
        ALLOCATE → Call ResourceAllocator with crisis_type + severity.
    """

    # Weight given to raw YOLO confidence when fused signals are also available
    _IMAGE_WEIGHT:  float = 0.6
    # Weight given to the fused (weather + social) score
    _FUSION_WEIGHT: float = 0.4

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
        fused_signal: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Process a detection result + optional fused signals, select an action,
        and allocate resources.

        Args:
            detection_result (Dict[str, Any]): Output from YOLODetector / FireAgent.
                Expected keys: 'detected' (bool), 'confidence' (float),
                'severity' (str), 'crisis_type' (str, optional),
                'location' (str, optional).
            fused_signal (Dict[str, Any], optional): Output from SignalFusion.fuse().
                When provided, blends weather + social scores with image confidence.

        Returns:
            Dict[str, Any]: Decision dict containing:
                - action          (str):           'evacuate' | 'warning' | 'monitor'.
                - confidence      (float):         Updated confidence score.
                - reasoning       (str):           Human-readable justification.
                - crisis_type     (str):           Crisis category used for allocation.
                - dominant_crisis (str):           Crisis type from fusion (or 'fire').
                - signal_sources  (list):          Which signal sources were used.
                - allocation      (Dict[str,Any]): ResourceAllocator output.
        """
        raw_confidence: float = float(detection_result.get("confidence", 0.0))
        detected:       bool  = bool(detection_result.get("detected", False))
        severity:       str   = detection_result.get("severity", "none")
        # Default crisis type falls back to 'fire' if not provided
        crisis_type:    str   = detection_result.get("crisis_type", "fire")
        location:       str   = detection_result.get("location", "Unknown Location")

        # ── OBSERVE ───────────────────────────────────────────────────
        observe_reasoning = (
            f"Detection received — detected={detected}, "
            f"confidence={raw_confidence:.2f}, severity={severity}, "
            f"crisis_type={crisis_type}"
        )
        if fused_signal:
            observe_reasoning += (
                f" | fused_score={fused_signal.get('fused_score', 0):.2f}, "
                f"dominant_crisis='{fused_signal.get('dominant_crisis', 'none')}'"
            )

        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="OBSERVE",
            reasoning=observe_reasoning,
            inputs={
                "detection_result": detection_result,
                "fused_signal": fused_signal,
            },
            output={},
            confidence_before=self.confidence,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=1,
        )

        # ── Blend image + fused scores ────────────────────────────────
        if fused_signal:
            fused_score:      float = float(fused_signal.get("fused_score", 0.0))
            dominant_crisis:  str   = fused_signal.get("dominant_crisis", "none")
            effective_conf:   float = (
                raw_confidence * self._IMAGE_WEIGHT +
                fused_score    * self._FUSION_WEIGHT
            )
            # Non-image crisis (flood/heatwave) can trigger even without YOLO fire
            effective_detected: bool = detected or (fused_score >= 0.5)
            # Override crisis type when fusion dominates
            if not detected and dominant_crisis not in ("none", "fire"):
                crisis_type = dominant_crisis
            signal_sources = ["image", "weather", "social"]
        else:
            effective_conf     = raw_confidence
            effective_detected = detected
            dominant_crisis    = crisis_type
            signal_sources     = ["image"]

        # ── DECIDE ────────────────────────────────────────────────────
        if effective_detected and effective_conf > 0.7:
            decision: Dict[str, Any] = {
                "action":     "evacuate",
                "confidence": min(effective_conf + 0.08, 1.0),
                "reasoning":  (
                    f"{crisis_type.capitalize()} detected with high confidence "
                    f"(effective_conf={effective_conf:.2f}) — immediate evacuation required"
                ),
            }
        elif effective_detected and effective_conf >= 0.4:
            decision = {
                "action":     "warning",
                "confidence": effective_conf,
                "reasoning":  (
                    f"Moderate {crisis_type} signals detected "
                    f"(effective_conf={effective_conf:.2f}) — issuing precautionary warning"
                ),
            }
        else:
            decision = {
                "action":     "monitor",
                "confidence": max(effective_conf, 0.30),
                "reasoning":  (
                    f"No significant {crisis_type} threat "
                    f"(effective_conf={effective_conf:.2f}) — continuing passive monitoring"
                ),
            }

        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="DECIDE",
            reasoning=decision["reasoning"],
            inputs={"effective_conf": effective_conf, "effective_detected": effective_detected},
            output=decision,
            confidence_before=self.confidence,
            confidence_after=decision["confidence"],
            tool_calls=[],
            duration_ms=1,
        )

        # ── ALLOCATE ─────────────────────────────────────────────────
        # Map action → severity tier expected by ResourceAllocator
        action_to_severity: Dict[str, str] = {
            "evacuate": "high",
            "warning":  "medium",
            "monitor":  "none",
        }
        alloc_severity = action_to_severity.get(decision["action"], severity)

        allocation = allocator.allocate(
            crisis_type=crisis_type,
            severity=alloc_severity,
            location=location,
        )

        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="ACT",
            reasoning=(
                f"ResourceAllocator dispatched {allocation['allocated_resources']} "
                f"with ETA={allocation['estimated_arrival_min']} min"
            ),
            inputs={"crisis_type": crisis_type, "severity": alloc_severity, "location": location},
            output=allocation,
            confidence_before=decision["confidence"],
            confidence_after=decision["confidence"],
            tool_calls=[],
            duration_ms=1,
        )

        # ── Compose final output ─────────────────────────────────────
        return {
            **decision,
            "crisis_type":     crisis_type,
            "dominant_crisis": dominant_crisis,
            "signal_sources":  signal_sources,
            "allocation":      allocation,
        }


# Module-level singleton
agent = DecisionAgent()

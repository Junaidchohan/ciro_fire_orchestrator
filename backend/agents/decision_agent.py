"""
decision_agent.py
-----------------
OODA-loop Decision Agent for the CIRO Fire Crisis Response System.

Responsibilities:
- Observe:  Distil raw YOLO detection results into a structured situation summary.
- Analyze:  Assess risk level and identify affected zones from the summary.
- Decide:   Recommend an action (evacuate / warning / monitor) with reasoning.
- Act:      Package the decision as a command payload for the Flutter frontend.
- Evaluate: Update internal confidence state based on reported outcomes.

Every method writes a structured entry via TraceLogger (rule-10).
All public methods return typed dicts — never raw text (rule-05).
"""

import time
from datetime import datetime
from typing import Any, Dict, List, Literal

from services.trace_logger import TraceLogger

# ── constants ─────────────────────────────────────────────────────────────────

# Risk thresholds (detection confidence → risk band)
_LOW_CONF_THRESHOLD: float = 0.45
_HIGH_CONF_THRESHOLD: float = 0.75

# Zone mapping: bounding-box screen quadrant → logical zone label
_ZONE_LABELS: Dict[str, str] = {
    "top-left":     "Zone A (North Wing)",
    "top-right":    "Zone B (East Wing)",
    "bottom-left":  "Zone C (South Wing)",
    "bottom-right": "Zone D (West Wing)",
    "center":       "Zone E (Central Hub)",
}

# Command verbs understood by the Flutter frontend (rule-05)
ActionType = Literal["EVACUATE", "WARNING", "MONITOR"]


# ── helpers ───────────────────────────────────────────────────────────────────

def _box_to_zone(box: Dict[str, Any], img_w: int = 640, img_h: int = 640) -> str:
    """
    Map a bounding-box dict (x1, y1, x2, y2) to a logical zone label.

    Args:
        box (dict): Bounding box with keys x1, y1, x2, y2.
        img_w (int): Image width in pixels (default 640).
        img_h (int): Image height in pixels (default 640).

    Returns:
        str: Human-readable zone label from ``_ZONE_LABELS``.
    """
    cx = (box["x1"] + box["x2"]) / 2
    cy = (box["y1"] + box["y2"]) / 2
    half_w, half_h = img_w / 2, img_h / 2
    margin = 0.15  # center band (±15 % of dimension)

    if abs(cx - half_w) < img_w * margin and abs(cy - half_h) < img_h * margin:
        return _ZONE_LABELS["center"]
    if cy < half_h:
        return _ZONE_LABELS["top-left"] if cx < half_w else _ZONE_LABELS["top-right"]
    return _ZONE_LABELS["bottom-left"] if cx < half_w else _ZONE_LABELS["bottom-right"]


# ── agent class ───────────────────────────────────────────────────────────────

class DecisionAgent:
    """
    Stateful OODA-loop agent that transforms fire-detection results into
    actionable commands and maintains an evolving confidence state.

    Attributes:
        confidence (float): Current confidence in the overall situation assessment.
                            Starts at 0.5 (neutral prior) and is updated by
                            ``evaluate()``.
        _logger (TraceLogger): Shared trace-logging service instance.
        _session_ts (str): ISO timestamp identifying this agent session.
    """

    def __init__(self) -> None:
        """Initialise the agent with a neutral confidence prior and a fresh TraceLogger."""
        self.confidence: float = 0.5
        self._session_ts: str = datetime.now().isoformat(timespec="seconds")
        self._logger: TraceLogger = TraceLogger()

    # ── observe ───────────────────────────────────────────────────────────────

    def observe(self, detection_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Distil raw YOLO detection output into a structured situation summary.

        Args:
            detection_results (dict): Payload from ``detect_fire()``, containing
                ``detected`` (bool), ``confidence`` (float), ``boxes`` (list).

        Returns:
            dict: Situation summary with keys:
                - fire_detected (bool)
                - detection_confidence (float)
                - box_count (int)
                - classes_seen (list[str])
                - timestamp (str)
        """
        t0 = time.monotonic()
        conf_before = self.confidence

        detected: bool = detection_results.get("detected", False)
        det_conf: float = detection_results.get("confidence", 0.0)
        boxes: List[Dict[str, Any]] = detection_results.get("boxes", [])
        classes_seen: List[str] = list({b.get("class", "unknown") for b in boxes})

        # Update internal confidence toward the detection confidence
        if detected:
            self.confidence = min(0.99, self.confidence + det_conf * 0.3)
        else:
            self.confidence = max(0.01, self.confidence - 0.05)

        summary: Dict[str, Any] = {
            "fire_detected": detected,
            "detection_confidence": det_conf,
            "box_count": len(boxes),
            "classes_seen": classes_seen,
            "timestamp": datetime.now().isoformat(timespec="milliseconds"),
        }

        duration_ms = int((time.monotonic() - t0) * 1000)
        self._logger.write_trace(
            agent_name="DecisionAgent",
            step_type="OBSERVE",
            reasoning=(
                f"Received detection payload. "
                f"Fire {'DETECTED' if detected else 'not detected'} with "
                f"confidence {det_conf:.2%}. "
                f"{len(boxes)} bounding box(es) found. "
                f"Classes: {classes_seen or ['none']}. "
                f"Internal confidence updated {conf_before:.3f} -> {self.confidence:.3f}."
            ),
            inputs={"detection_results": detection_results},
            output=summary,
            confidence_before=conf_before,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=duration_ms,
        )
        return summary

    # ── analyze ───────────────────────────────────────────────────────────────

    def analyze(self, situation_summary: Dict[str, Any]) -> Dict[str, Any]:
        """
        Assess risk level and identify affected zones from a situation summary.

        Args:
            situation_summary (dict): Output of ``observe()``.

        Returns:
            dict: Risk analysis with keys:
                - risk_level ("low" | "medium" | "high")
                - affected_zones (list[str])
                - spread_risk (bool)
                - analysis_notes (str)
        """
        t0 = time.monotonic()
        conf_before = self.confidence

        det_conf: float = situation_summary.get("detection_confidence", 0.0)
        box_count: int = situation_summary.get("box_count", 0)
        fire_detected: bool = situation_summary.get("fire_detected", False)

        # Risk band classification
        if not fire_detected or det_conf < _LOW_CONF_THRESHOLD:
            risk_level: str = "low"
        elif det_conf < _HIGH_CONF_THRESHOLD or box_count <= 1:
            risk_level = "medium"
        else:
            risk_level = "high"

        # Carry raw boxes through the pipeline for zone mapping
        raw_boxes: List[Dict[str, Any]] = situation_summary.get("boxes", [])
        affected_zones: List[str] = (
            list({_box_to_zone(b) for b in raw_boxes})
            if raw_boxes
            else (["Zone E (Central Hub)"] if fire_detected else [])
        )

        spread_risk: bool = box_count >= 2 or risk_level == "high"

        notes = (
            f"Risk classified as '{risk_level}' based on detection confidence "
            f"{det_conf:.2%} and {box_count} active detection(s). "
            f"Affected zones: {affected_zones or ['none']}. "
            f"Spread risk: {'YES' if spread_risk else 'no'}."
        )

        # Confidence nudge based on risk certainty
        if risk_level == "high":
            self.confidence = min(0.99, self.confidence + 0.05)
        elif risk_level == "low":
            self.confidence = max(0.01, self.confidence - 0.03)

        analysis: Dict[str, Any] = {
            "risk_level": risk_level,
            "affected_zones": affected_zones,
            "spread_risk": spread_risk,
            "analysis_notes": notes,
        }

        duration_ms = int((time.monotonic() - t0) * 1000)
        self._logger.write_trace(
            agent_name="DecisionAgent",
            step_type="ANALYZE",
            reasoning=notes,
            inputs={"situation_summary": situation_summary},
            output=analysis,
            confidence_before=conf_before,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=duration_ms,
        )
        return analysis

    # ── decide ────────────────────────────────────────────────────────────────

    def decide(self, risk_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """
        Recommend an action based on the risk analysis.

        Args:
            risk_analysis (dict): Output of ``analyze()``.

        Returns:
            dict: Decision with keys:
                - action (ActionType)
                - priority (int 1-3, 1 = highest)
                - recommendation (str)
                - affected_zones (list[str])
        """
        t0 = time.monotonic()
        conf_before = self.confidence

        risk_level: str = risk_analysis.get("risk_level", "low")
        affected_zones: List[str] = risk_analysis.get("affected_zones", [])
        spread_risk: bool = risk_analysis.get("spread_risk", False)

        action_map: Dict[str, str] = {
            "high":   "EVACUATE",
            "medium": "WARNING",
            "low":    "MONITOR",
        }
        priority_map: Dict[str, int] = {"high": 1, "medium": 2, "low": 3}

        action: str = action_map.get(risk_level, "MONITOR")
        priority: int = priority_map.get(risk_level, 3)

        recommendation = (
            f"Action '{action}' selected (priority {priority}). "
            f"Risk level: {risk_level.upper()}. "
            f"Zones affected: {affected_zones or ['none']}. "
            f"Spread risk: {'HIGH - immediate containment required' if spread_risk else 'LOW - standard protocol'}."
        )

        # Committing to a decision lowers uncertainty slightly
        self.confidence = min(0.99, self.confidence + 0.02)

        decision: Dict[str, Any] = {
            "action": action,
            "priority": priority,
            "recommendation": recommendation,
            "affected_zones": affected_zones,
        }

        duration_ms = int((time.monotonic() - t0) * 1000)
        self._logger.write_trace(
            agent_name="DecisionAgent",
            step_type="DECIDE",
            reasoning=recommendation,
            inputs={"risk_analysis": risk_analysis},
            output=decision,
            confidence_before=conf_before,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=duration_ms,
        )
        return decision

    # ── act ───────────────────────────────────────────────────────────────────

    def act(self, decision: Dict[str, Any]) -> Dict[str, Any]:
        """
        Package the decision into a command payload for the Flutter frontend.

        Args:
            decision (dict): Output of ``decide()``.

        Returns:
            dict: Frontend command payload with keys:
                - command (str)
                - action (str)
                - priority (int)
                - zones (list[str])
                - message (str)
                - confidence (float)
                - issued_at (str)
        """
        t0 = time.monotonic()
        conf_before = self.confidence

        action: str = decision.get("action", "MONITOR")
        priority: int = decision.get("priority", 3)
        zones: List[str] = decision.get("affected_zones", [])

        # Human-readable alert messages for the Flutter UI
        messages: Dict[str, str] = {
            "EVACUATE": "EVACUATE IMMEDIATELY - Fire confirmed. All personnel must leave affected zones now.",
            "WARNING":  "FIRE WARNING - Possible fire detected. Prepare for evacuation. Await further instruction.",
            "MONITOR":  "MONITORING - Low-confidence detection. Surveillance increased; no action required yet.",
        }

        command_payload: Dict[str, Any] = {
            "command": f"DISPATCH_{action}",
            "action": action,
            "priority": priority,
            "zones": zones,
            "message": messages.get(action, "Status update issued."),
            "confidence": round(self.confidence, 4),
            "issued_at": datetime.now().isoformat(timespec="milliseconds"),
        }

        duration_ms = int((time.monotonic() - t0) * 1000)
        self._logger.write_trace(
            agent_name="DecisionAgent",
            step_type="ACT",
            reasoning=(
                f"Command '{command_payload['command']}' dispatched to frontend. "
                f"Priority {priority}, zones: {zones or ['none']}. "
                f"Agent confidence at dispatch: {self.confidence:.3f}."
            ),
            inputs={"decision": decision},
            output=command_payload,
            confidence_before=conf_before,
            confidence_after=self.confidence,
            tool_calls=[{"tool": "FrontendDispatch", "command": command_payload["command"]}],
            duration_ms=duration_ms,
        )
        return command_payload

    # ── evaluate ──────────────────────────────────────────────────────────────

    def evaluate(self, outcome: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update the agent's confidence state based on reported outcome feedback.

        Args:
            outcome (dict): Feedback payload with optional keys:
                - confirmed (bool) - True if the fire was independently confirmed.
                - false_positive (bool) - True if the alert was a false alarm.
                - resolution (str) - Free-text description of what happened.

        Returns:
            dict: Evaluation result with keys:
                - confidence_before (float)
                - confidence_after (float)
                - verdict (str)
                - notes (str)
        """
        t0 = time.monotonic()
        conf_before = self.confidence

        confirmed: bool = outcome.get("confirmed", False)
        false_positive: bool = outcome.get("false_positive", False)
        resolution: str = outcome.get("resolution", "No resolution provided.")

        if confirmed:
            # Correct call — reinforce confidence
            self.confidence = min(0.99, self.confidence + 0.10)
            verdict = "CORRECT"
            notes = f"Alert confirmed. Confidence reinforced. Resolution: {resolution}"
        elif false_positive:
            # Wrong call — penalise confidence
            self.confidence = max(0.01, self.confidence - 0.15)
            verdict = "FALSE_POSITIVE"
            notes = f"False alarm registered. Confidence penalised. Resolution: {resolution}"
        else:
            # Ambiguous outcome — nudge toward neutral
            delta = (0.5 - self.confidence) * 0.1
            self.confidence = round(self.confidence + delta, 4)
            verdict = "AMBIGUOUS"
            notes = f"Outcome unclear; confidence nudged toward neutral. Resolution: {resolution}"

        eval_result: Dict[str, Any] = {
            "confidence_before": round(conf_before, 4),
            "confidence_after": round(self.confidence, 4),
            "verdict": verdict,
            "notes": notes,
        }

        duration_ms = int((time.monotonic() - t0) * 1000)
        self._logger.write_trace(
            agent_name="DecisionAgent",
            step_type="EVALUATE",
            reasoning=notes,
            inputs={"outcome": outcome},
            output=eval_result,
            confidence_before=conf_before,
            confidence_after=self.confidence,
            tool_calls=[],
            duration_ms=duration_ms,
        )
        return eval_result

    # ── convenience: run full OODA loop ───────────────────────────────────────

    def run_pipeline(self, detection_results: Dict[str, Any]) -> Dict[str, Any]:
        """
        Execute the full Observe -> Analyze -> Decide -> Act pipeline in sequence.

        Args:
            detection_results (dict): Raw output from ``detect_fire()``.

        Returns:
            dict: Combined pipeline result with keys from all four stages plus
                  agent_confidence and session_timestamp.
        """
        situation = self.observe(detection_results)

        # Carry raw boxes forward so analyze() can map them to zones
        situation["boxes"] = detection_results.get("boxes", [])

        risk = self.analyze(situation)
        decision = self.decide(risk)
        command = self.act(decision)

        return {
            "situation": situation,
            "risk": risk,
            "decision": decision,
            "command": command,
            "agent_confidence": round(self.confidence, 4),
            "session_timestamp": self._session_ts,
        }

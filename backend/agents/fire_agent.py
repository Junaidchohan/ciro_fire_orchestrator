import time
from agents.base_agent import BaseAgent
from services.yolo_detector import detector


class FireAgent(BaseAgent):
    """
    OODA-loop agent responsible for end-to-end fire detection and response.

    Pipeline:
        observe  → extract image path and capture timestamp
        analyze  → run YOLOv8 inference via the module-level detector singleton
        decide   → map severity/confidence to an actionable response level
        act      → record the taken action with a timestamp
        evaluate → confirm success and surface a structured outcome

    Each step emits a trace entry via BaseAgent.logger (TraceLogger) so the
    hackathon audit trail is always complete.
    """

    # Confidence thresholds used in decide()
    _HIGH_CONFIDENCE: float = 0.85
    _MEDIUM_CONFIDENCE: float = 0.70

    def __init__(self) -> None:
        """Initialise the agent and inherit the TraceLogger from BaseAgent."""
        super().__init__("fire_agent")

    # ------------------------------------------------------------------
    # OODA Steps
    # ------------------------------------------------------------------

    async def observe(self, data: dict) -> dict:
        """
        Extract the image path and capture a wall-clock timestamp.

        Args:
            data: Raw input dict expected to contain an 'image' key with
                  the path (str) to the image file to analyse.

        Returns:
            Dict with keys:
                - image (str | None): Path to the image.
                - timestamp (float): Unix epoch at observation time.
        """
        obs = {
            "image": data.get("image"),
            "timestamp": time.time(),
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="OBSERVE",
            reasoning=f"Image path received: {obs['image']}",
            confidence_before=0.0,
            confidence_after=0.5,
        )
        return obs

    async def analyze(self, obs: dict) -> dict:
        """
        Run YOLOv8 fire/smoke detection on the observed image.

        Args:
            obs: Output of observe(); must contain an 'image' key.

        Returns:
            Dict with keys:
                - detected (bool): Whether fire/smoke was found.
                - confidence (float): Top detection confidence (0–1).
                - severity (str): 'high' | 'medium' | 'low' | 'none'.
                - recommendation (str): Suggested action from detector.
        """
        result = detector.detect_fire(obs["image"])
        analysis = {
            "detected": result["detected"],
            "confidence": result["confidence"],
            "severity": result["severity"],
            "recommendation": result["recommendation"],
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="ANALYZE",
            reasoning=(
                f"YOLO result – detected={analysis['detected']}, "
                f"confidence={analysis['confidence']:.2f}, "
                f"severity={analysis['severity']}"
            ),
            confidence_before=0.5,
            confidence_after=analysis["confidence"],
        )
        return analysis

    async def decide(self, analysis: dict) -> dict:
        """
        Map detection analysis to a concrete response action.

        Decision matrix (aligned with YOLODetector severity thresholds):
            severity 'high'   (≥ 0.85) → action 'alert',   severity 'high'
            severity 'medium' (≥ 0.70) → action 'alert',   severity 'medium'
            severity 'low'   (≥ 0.50) → action 'warn',    severity 'low'
            otherwise                  → action 'monitor', severity 'none'

        Args:
            analysis: Output of analyze().

        Returns:
            Dict with keys:
                - action (str): 'alert' | 'warn' | 'monitor'.
                - severity (str): Mirrors analysis severity.
                - recommendation (str): Human-readable suggestion.
                - confidence (float): Confidence carried forward.
        """
        severity = analysis["severity"]
        confidence = analysis["confidence"]

        if severity == "high":
            decision = {
                "action": "alert",
                "severity": "high",
                "recommendation": analysis["recommendation"],
                "confidence": confidence,
            }
        elif severity == "medium":
            decision = {
                "action": "alert",
                "severity": "medium",
                "recommendation": analysis["recommendation"],
                "confidence": confidence,
            }
        elif severity == "low":
            decision = {
                "action": "warn",
                "severity": "low",
                "recommendation": analysis["recommendation"],
                "confidence": confidence,
            }
        else:
            decision = {
                "action": "monitor",
                "severity": "none",
                "recommendation": "No action required",
                "confidence": confidence,
            }

        self.logger.write_trace(
            agent_name=self.name,
            step_type="DECIDE",
            reasoning=(
                f"Action '{decision['action']}' chosen for severity "
                f"'{severity}' (confidence={confidence:.2f})"
            ),
            confidence_before=analysis["confidence"],
            confidence_after=confidence,
        )
        return decision

    async def act(self, decision: dict) -> dict:
        """
        Record the execution of the decided action with a timestamp.

        Args:
            decision: Output of decide().

        Returns:
            Dict with keys:
                - action_taken (str): The action that was executed.
                - severity (str): Severity level at execution time.
                - recommendation (str): Carried-forward recommendation.
                - timestamp (float): Unix epoch when the action was taken.
        """
        result = {
            "action_taken": decision["action"],
            "severity": decision["severity"],
            "recommendation": decision["recommendation"],
            "timestamp": time.time(),
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="ACT",
            reasoning=f"Executing action '{result['action_taken']}' at t={result['timestamp']:.2f}",
            confidence_before=decision["confidence"],
            confidence_after=decision["confidence"],
        )
        return result

    async def evaluate(self, result: dict) -> dict:
        """
        Confirm the action completed successfully and return a final summary.

        Args:
            result: Output of act().

        Returns:
            Typed JSON-serialisable dict with keys:
                - success (bool): Always True if this step is reached.
                - action (str): Action that was taken.
                - severity (str): Final severity label.
                - recommendation (str): Recommendation surfaced to callers.
        """
        evaluation = {
            "success": True,
            "action": result["action_taken"],
            "severity": result["severity"],
            "recommendation": result["recommendation"],
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="EVALUATE",
            reasoning=f"Cycle complete – action='{evaluation['action']}', success=True",
            confidence_before=0.9,
            confidence_after=1.0,
        )
        return evaluation


# Module-level singleton – import and use `fire_agent` directly
fire_agent = FireAgent()

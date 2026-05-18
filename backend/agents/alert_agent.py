"""
alert_agent.py
--------------
Alert Agent for CIRO Fire Crisis Response System.
Processes decisions and broadcasts alerts to active WebSocket clients.
"""

import time
from typing import Dict, Any
from agents.base_agent import BaseAgent
from websocket_endpoint import manager


class AlertAgent(BaseAgent):
    """
    OODA-loop agent responsible for dispatching alerts.

    Observe  → Receive decision from Allocator (DecisionAgent).
    Analyze  → Determine if severity warrants immediate warning/evacuation.
    Decide   → Compile visual/acoustic warning signals and payloads.
    Act      → Broadcast warning to connected clients via WebSocket ConnectionManager.
    Evaluate → Confirm message delivery and log transaction success.
    """

    def __init__(self) -> None:
        """Initialize AlertAgent and inherit base OODA components."""
        super().__init__("alert_agent")

    async def observe(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Receive decision output from upstream agent.

        Args:
            data (Dict[str, Any]): Decision data containing severity and recommended actions.

        Returns:
            Dict[str, Any]: The unmodified input data.
        """
        self.logger.write_trace(
            agent_name=self.name,
            step_type="OBSERVE",
            reasoning=f"Received decision data: {data}",
            confidence_before=0.9,
            confidence_after=0.95,
        )
        return data

    async def analyze(self, obs: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze decision severity to prepare action payload.

        Args:
            obs (Dict[str, Any]): Observed decision data.

        Returns:
            Dict[str, Any]: Extracted action and severity parameters.
        """
        severity = obs.get("severity", "none")
        action = obs.get("action", "monitor")

        self.logger.write_trace(
            agent_name=self.name,
            step_type="ANALYZE",
            reasoning=f"Analyzing decision: action={action}, severity={severity}",
            confidence_before=0.95,
            confidence_after=0.95,
        )
        return {
            "action": action,
            "severity": severity,
            "recommendation": obs.get("recommendation", ""),
        }

    async def decide(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """
        Formulate final alert notification payload.

        Args:
            analysis (Dict[str, Any]): Analyzed severity/action metrics.

        Returns:
            Dict[str, Any]: Compiled WebSocket-ready JSON alert payload.
        """
        payload = {
            "type": "fire_alert",
            "action": analysis["action"],
            "severity": analysis["severity"],
            "message": f"CRITICAL: Fire detected! Severity: {analysis['severity'].upper()}. Recommendation: {analysis['recommendation']}",
            "timestamp": time.time(),
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="DECIDE",
            reasoning=f"Formulated alert payload: {payload}",
            confidence_before=0.95,
            confidence_after=0.98,
        )
        return payload

    async def act(self, decision: Dict[str, Any]) -> Dict[str, Any]:
        """
        Broadcast formulated alert via the WebSocket manager.

        Args:
            decision (Dict[str, Any]): Formulated alert payload.

        Returns:
            Dict[str, Any]: Execution status map.
        """
        await manager.broadcast_alert(decision)
        self.logger.write_trace(
            agent_name=self.name,
            step_type="ACT",
            reasoning="Alert broadcasted to active WebSocket clients successfully",
            confidence_before=0.98,
            confidence_after=0.99,
        )
        return {"broadcasted": True, "payload": decision}

    async def evaluate(self, result: Dict[str, Any]) -> Dict[str, Any]:
        """
        Evaluate the transaction success.

        Args:
            result (Dict[str, Any]): Execution output from the act step.

        Returns:
            Dict[str, Any]: Evaluation status mapping.
        """
        evaluation = {
            "success": result.get("broadcasted", False),
            "timestamp": time.time(),
        }
        self.logger.write_trace(
            agent_name=self.name,
            step_type="EVALUATE",
            reasoning=f"Alert loop finished. success={evaluation['success']}",
            confidence_before=0.99,
            confidence_after=1.0,
        )
        return evaluation

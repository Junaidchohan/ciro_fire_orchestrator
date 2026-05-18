"""
Orchestrator Agent for CIRO Fire Crisis Response System.

Coordinates the pipeline: FireAgent → DecisionAgent → AlertAgent
in a continuous async loop. Logs every lifecycle event via TraceLogger.
"""

from agents.fire_agent import FireAgent
from agents.decision_agent import DecisionAgent
from agents.alert_agent import AlertAgent
from services.trace_logger import TraceLogger
import asyncio


class Orchestrator:
    """
    Top-level controller that drives the agent pipeline.

    Pipeline (rule-11):
        fusion → classifier (FireAgent)
               → allocator  (DecisionAgent)
               → simulator  (AlertAgent)
    """

    def __init__(self) -> None:
        """Initialise all sub-agents and the shared trace logger."""
        self.fire: FireAgent = FireAgent()
        self.decision: DecisionAgent = DecisionAgent()
        self.alert: AlertAgent = AlertAgent()
        self.logger: TraceLogger = TraceLogger()
        self.running: bool = False

    async def start(self) -> None:
        """
        Enter the main production loop.

        Polls FireAgent every second. When an alert action is returned,
        forwards the result through DecisionAgent → AlertAgent and logs
        the outcome.
        """
        self.running = True
        self.logger.write_trace(
            agent_name="orchestrator",
            step_type="ACT",
            reasoning="Production mode ON — entering continuous detection loop",
            confidence_before=0.9,
            confidence_after=0.9,
        )

        while self.running:
            # OBSERVE — run fire detection
            result: dict = await self.fire.run({"mode": "continuous"})

            if result.get("action") == "alert":
                # DECIDE — evaluate severity and allocate resources
                decision: dict = await self.decision.run(result)

                # ACT — dispatch alert to downstream systems
                await self.alert.run(decision)

                self.logger.write_trace(
                    agent_name="orchestrator",
                    step_type="DECIDE",
                    reasoning=f"Alert dispatched: {decision}",
                    confidence_before=0.9,
                    confidence_after=0.95,
                )

            await asyncio.sleep(1)

    async def stop(self) -> None:
        """
        Gracefully exit the production loop and log the shutdown event.
        """
        self.running = False
        self.logger.write_trace(
            agent_name="orchestrator",
            step_type="EVALUATE",
            reasoning="Production mode OFF — loop terminated cleanly",
            confidence_before=0.9,
            confidence_after=0.9,
        )


# Module-level singleton (consumed by FastAPI lifespan / routes)
orchestrator = Orchestrator()

from abc import ABC, abstractmethod
from services.trace_logger import TraceLogger
import time


class BaseAgent(ABC):
    """
    Abstract base class for all CIRO agents.

    Implements the OODA-style loop: Observe → Analyze → Decide → Act → Evaluate.
    Each step is trace-logged for hackathon audit trails. Subclasses must
    implement all five abstract methods.
    """

    def __init__(self, name: str):
        """
        Initialize the agent with a name, trace logger, and retry state.

        Args:
            name: Human-readable agent identifier used in trace logs.
        """
        self.name = name
        self.logger = TraceLogger()
        self.state = "idle"
        self.retries = 0
        self.max_retries = 3

    @abstractmethod
    async def observe(self, data): pass

    @abstractmethod
    async def analyze(self, obs): pass

    @abstractmethod
    async def decide(self, analysis): pass

    @abstractmethod
    async def act(self, decision): pass

    @abstractmethod
    async def evaluate(self, result): pass

    async def run(self, input_data):
        """
        Execute the full agent loop with automatic retry on failure.

        Progresses through observe → analyze → decide → act → evaluate,
        writing a trace log at each step. On exception, retries up to
        max_retries times before re-raising.

        Args:
            input_data: Raw input passed to the observe step.

        Returns:
            The evaluation result from the evaluate step.

        Raises:
            Exception: Re-raised after max_retries are exhausted.
        """
        try:
            self.state = "observing"
            self.logger.write_trace(self.name, "OBSERVE", f"Input: {input_data}", 0.5)
            obs = await self.observe(input_data)

            self.state = "analyzing"
            self.logger.write_trace(self.name, "ANALYZE", f"Obs: {obs}", 0.6)
            analysis = await self.analyze(obs)

            self.state = "deciding"
            self.logger.write_trace(self.name, "DECIDE", f"Analysis: {analysis}", 0.7)
            decision = await self.decide(analysis)

            self.state = "acting"
            self.logger.write_trace(self.name, "ACT", f"Decision: {decision}", 0.8)
            result = await self.act(decision)

            self.state = "evaluating"
            self.logger.write_trace(self.name, "EVALUATE", f"Result: {result}", 0.85)
            evaluation = await self.evaluate(result)

            return evaluation

        except Exception as e:
            if self.retries < self.max_retries:
                self.retries += 1
                return await self.run(input_data)
            raise e

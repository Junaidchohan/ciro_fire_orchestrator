from abc import ABC, abstractmethod

class BaseAgent(ABC):
    def __init__(self, name: str = None):
        self.name = name

    @abstractmethod
    def analyze(self, data: dict) -> dict:
        pass

    @abstractmethod
    def decide(self, analysis: dict) -> dict:
        pass

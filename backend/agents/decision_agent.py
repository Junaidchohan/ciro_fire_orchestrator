from services.trace_logger import TraceLogger
import time

class DecisionAgent:
    def __init__(self):
        self.logger = TraceLogger()
        self.confidence = 0.5
    
    def decide(self, detection_result):
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="OBSERVE",
            reasoning=f"Detection confidence: {detection_result['confidence']}",
            confidence_before=self.confidence,
            confidence_after=self.confidence
        )
        
        if detection_result['detected'] and detection_result['confidence'] > 0.7:
            decision = {"action": "evacuate", "confidence": 0.92, "reasoning": "Fire detected with high confidence"}
        elif detection_result['detected']:
            decision = {"action": "warning", "confidence": 0.75, "reasoning": "Possible fire detected"}
        else:
            decision = {"action": "monitor", "confidence": 0.60, "reasoning": "No fire detected"}
        
        self.logger.write_trace(
            agent_name="decision_agent",
            step_type="DECIDE",
            reasoning=decision['reasoning'],
            confidence_before=self.confidence,
            confidence_after=decision['confidence']
        )
        return decision

agent = DecisionAgent()

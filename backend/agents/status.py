"""
status.py
---------
Provides AgentMemory to track agent actions and status endpoints.
"""

import json
import os
from datetime import datetime
from typing import Any, Dict, List

class AgentMemory:
    """
    Agent Memory class to record agent actions and outcomes.
    Persists data in a local JSON log file.
    """

    def __init__(self) -> None:
        """
        Initialises AgentMemory, setting the storage file path
        and ensuring the directory exists.
        """
        self.file: str = "logs/agent_memory.json"
        # Ensure log directory exists
        os.makedirs(os.path.dirname(self.file), exist_ok=True)
    
    def save(self, agent: str, action: str, outcome: str) -> None:
        """
        Saves an agent action and its outcome to the memory file.
        Limits the total saved memories to the last 100 entries.

        Args:
            agent (str): The name of the agent.
            action (str): The action performed by the agent.
            outcome (str): The outcome of the action.
        """
        try:
            with open(self.file, "r", encoding="utf-8") as f:
                mem: List[Dict[str, Any]] = json.load(f)
        except Exception:
            mem = []
        
        mem.append({
            "agent": agent,
            "action": action,
            "outcome": outcome,
            "time": datetime.now().isoformat()
        })
        
        with open(self.file, "w", encoding="utf-8") as f:
            json.dump(mem[-100:], f, indent=2, ensure_ascii=False)

# Module-level singleton
memory: AgentMemory = AgentMemory()

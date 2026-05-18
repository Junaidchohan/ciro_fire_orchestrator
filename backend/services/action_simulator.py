"""
action_simulator.py
-------------------
Action Simulation Service for CIRO Fire Crisis Response System.

Computes before/after crisis state based on allocated resources,
logs the simulation decision via TraceLogger, and returns structured
impact metrics for downstream display.
"""

import time
from typing import Any, Dict, List

from services.trace_logger import TraceLogger


# ── resource-type weights for impact scoring ──────────────────────────────────
_RESOURCE_IMPACT: Dict[str, float] = {
    "fire_trucks": 0.20,
    "ambulances": 0.10,
    "police_units": 0.08,
    "helicopters": 0.15,
    "hazmat_teams": 0.12,
    "water_tankers": 0.18,
}

# Crisis-specific baseline populations and damage labels
_CRISIS_BASELINE: Dict[str, Dict[str, Any]] = {
    "fire": {
        "affected_population": 5000,
        "estimated_damage": "high",
        "traffic_congestion": "severe",
    },
    "flood": {
        "affected_population": 12000,
        "estimated_damage": "critical",
        "traffic_congestion": "severe",
    },
    "heatwave": {
        "affected_population": 30000,
        "estimated_damage": "moderate",
        "traffic_congestion": "moderate",
    },
    "default": {
        "affected_population": 5000,
        "estimated_damage": "high",
        "traffic_congestion": "severe",
    },
}

_DAMAGE_LEVELS = ["critical", "high", "medium", "low", "minimal"]
_CONGESTION_LEVELS = ["severe", "moderate", "mild", "clear"]


def _reduce_label(labels: List[str], current: str, steps: int) -> str:
    """Move `current` label toward better end of list by `steps` positions."""
    try:
        idx = labels.index(current)
    except ValueError:
        return current
    return labels[max(0, idx + steps)]


class ActionSimulator:
    """
    Simulates the before/after crisis state given allocated emergency resources.

    Uses a simple impact-scoring model to estimate population reduction,
    congestion improvement, and damage downgrade. All decisions are written
    to the TraceLogger for hackathon audit trails.
    """

    def __init__(self) -> None:
        """Initialize with a shared TraceLogger instance."""
        self._logger = TraceLogger()

    # ── public API ────────────────────────────────────────────────────────────

    def simulate(
        self,
        crisis_type: str,
        allocated_resources: Dict[str, Any],
        location: str = "Unknown",
    ) -> Dict[str, Any]:
        """
        Compute before/after crisis state and return a structured simulation result.

        Args:
            crisis_type (str): Type of crisis (e.g., 'fire', 'flood', 'heatwave').
            allocated_resources (Dict[str, Any]): Map of resource name → quantity/details.
            location (str): Incident location label for contextual logging.

        Returns:
            Dict[str, Any]: Simulation payload with before, after, actions_taken,
                            impact_metrics, and simulation_time_seconds.
        """
        t_start = time.time()

        # ── before state ──────────────────────────────────────────────────────
        baseline = _CRISIS_BASELINE.get(crisis_type.lower(), _CRISIS_BASELINE["default"])

        before: Dict[str, Any] = {
            "affected_population": baseline["affected_population"],
            "traffic_congestion": baseline["traffic_congestion"],
            "emergency_response": "not_dispatched",
            "estimated_damage": baseline["estimated_damage"],
        }

        # ── compute impact from allocated resources ────────────────────────────
        total_impact_score = self._compute_impact(allocated_resources)

        # Scale: 0 resources → 0 reduction; max resources → ~80 % reduction
        population_reduction_pct = min(0.80, total_impact_score)
        after_population = int(
            before["affected_population"] * (1.0 - population_reduction_pct)
        )

        # Congestion improvement: every 0.15 impact → 1 level better
        congestion_steps = int(total_impact_score / 0.15)
        after_congestion = _reduce_label(
            _CONGESTION_LEVELS, before["traffic_congestion"], congestion_steps
        )

        # Damage improvement: every 0.20 impact → 1 level better
        damage_steps = int(total_impact_score / 0.20)
        after_damage = _reduce_label(
            _DAMAGE_LEVELS, before["estimated_damage"], damage_steps
        )

        response_time_improvement = int(population_reduction_pct * 100)

        # ── after state ───────────────────────────────────────────────────────
        after: Dict[str, Any] = {
            "affected_population": after_population,
            "traffic_congestion": after_congestion,
            "emergency_response": "dispatched",
            "estimated_damage": after_damage,
            "improvement": f"{response_time_improvement}% reduction in response time",
        }

        # ── impact metrics (for UI display) ──────────────────────────────────
        impact_metrics: Dict[str, Any] = {
            "response_time_improvement_pct": response_time_improvement,
            "population_protected": before["affected_population"] - after_population,
            "congestion_reduced": before["traffic_congestion"] != after_congestion,
            "damage_downgraded": before["estimated_damage"] != after_damage,
            "total_resources_deployed": sum(
                v if isinstance(v, int) else 1
                for v in allocated_resources.values()
            ),
        }

        simulation_seconds = round(time.time() - t_start + 120, 1)  # mock: simulated 2-min horizon

        result: Dict[str, Any] = {
            "before": before,
            "after": after,
            "actions_taken": allocated_resources,
            "impact_metrics": impact_metrics,
            "simulation_time_seconds": simulation_seconds,
        }

        # ── trace log ─────────────────────────────────────────────────────────
        self._logger.write_trace(
            agent_name="action_simulator",
            step_type="SIMULATE",
            reasoning=(
                f"Crisis '{crisis_type}' at '{location}'. "
                f"Impact score={total_impact_score:.2f}. "
                f"Population reduced by {response_time_improvement}%. "
                f"Damage: {before['estimated_damage']} → {after_damage}. "
                f"Congestion: {before['traffic_congestion']} → {after_congestion}."
            ),
            inputs={"crisis_type": crisis_type, "location": location, "resources": allocated_resources},
            output=result,
            confidence_before=0.70,
            confidence_after=0.90,
            tool_calls=[],
            duration_ms=int((time.time() - t_start) * 1000),
        )

        return result

    # ── private helpers ───────────────────────────────────────────────────────

    def _compute_impact(self, resources: Dict[str, Any]) -> float:
        """
        Compute a normalised impact score [0, 1] from deployed resource quantities.

        Args:
            resources (Dict[str, Any]): Allocated resource map.

        Returns:
            float: Normalised impact score.
        """
        score = 0.0
        for resource_name, value in resources.items():
            quantity = value if isinstance(value, (int, float)) else 1
            weight = _RESOURCE_IMPACT.get(resource_name.lower(), 0.05)
            score += weight * min(quantity, 5)  # cap at 5 units per type

        return min(1.0, score)


# ── module-level singleton ────────────────────────────────────────────────────
simulator = ActionSimulator()

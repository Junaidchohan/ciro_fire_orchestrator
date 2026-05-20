
"""
Orchestrator Agent for CIRO Fire Crisis Response System.

Coordinates the pipeline: FireAgent → DecisionAgent → AlertAgent
in a continuous async loop. Logs every lifecycle event via TraceLogger.

Added functionalities:
- Resource Allocation
- Action Simulation
- Stakeholder Notifications
"""

from agents.fire_agent import FireAgent
from agents.decision_agent import DecisionAgent
from agents.alert_agent import AlertAgent
from services.trace_logger import TraceLogger
import asyncio
import random # Added for mock data generation


def _mock_distance_calculator(loc1: str, loc2: str) -> float:
    """Mock distance calculation."""
    # In a real system, this would use an API (e.g., Google Maps)
    # For now, return a random distance between 1 and 20 km
    return random.uniform(1.0, 20.0)


def allocate_resources(crises: list, available_units: dict) -> dict:
    """
    Allocates resources based on severity and proximity.

    Args:
        crises: List of active crisis dictionaries (must contain 'id', 'severity', 'location').
        available_units: Dictionary of available resources (e.g., {"ambulances": 5}).

    Returns:
        Dictionary mapping crisis IDs to allocated resources.
    """
    allocation_plan = {}

    # Define a central dispatch location for distance calculations
    DISPATCH_CENTER = "Central Station"

    # Sort crises by severity (descending) and then distance (ascending)
    sorted_crises = sorted(
        crises,
        key=lambda c: (
            -float(c.get("severity", 0)), # Ensure numerical comparison, handle potential strings
             _mock_distance_calculator(c.get("location", "Unknown"), DISPATCH_CENTER)
        )
    )

    # Simple greedy allocation (for demonstration)
    for crisis in sorted_crises:
        crisis_id = crisis.get("id", "unknown_crisis")
        allocation_plan[crisis_id] = {}

        # Determine needs based on type and severity (simplified logic)
        crisis_type = crisis.get("type", "").lower()
        severity = float(crisis.get("severity", 0))

        needed = {}
        if crisis_type == "fire":
            if severity > 0.7: needed = {"fire_trucks": 3, "ambulances": 2, "police": 1}
            else: needed = {"fire_trucks": 1, "police": 1}
        elif crisis_type == "flood":
             if severity > 0.6: needed = {"rescue_boats": 2, "police": 3}
             else: needed = {"police": 1}
        else: # Generic need
            needed = {"police": 1}

        # Allocate based on availability
        for resource, count in needed.items():
            if available_units.get(resource, 0) > 0:
                allocated = min(count, available_units[resource])
                allocation_plan[crisis_id][resource] = allocated
                available_units[resource] -= allocated

    return allocation_plan


def simulate_action(allocation_plan: dict, crisis: dict) -> dict:
    """
    Simulates the impact of the allocated resources on the crisis.
    """
    # Simple mock logic for simulation outcomes
    crisis_id = crisis.get("id")
    allocated = allocation_plan.get(crisis_id, {})
    total_resources = sum(allocated.values())

    eta_reduction = min(total_resources * 2.5, 20) # Max 20 min reduction

    traffic_reroute = True if total_resources > 2 else False

    side_effects = "Minimal impact on surrounding sectors."
    if traffic_reroute:
         side_effects = f"Moderate congestion expected near {crisis.get('location', 'the incident area')} due to rerouting."

    return {
        "traffic_reroute": traffic_reroute,
        "eta_reduction_minutes": round(eta_reduction, 1),
        "side_effects": side_effects
    }

def generate_notifications(crisis: dict, allocation_plan: dict, simulation: dict) -> list:
    """
    Generates targeted notifications based on the crisis plan.
    """
    notifications = []
    crisis_type = crisis.get("type", "incident")
    location = crisis.get("location", "an unspecified location")
    severity = float(crisis.get("severity", 0))
    crisis_id = crisis.get("id")
    allocated = allocation_plan.get(crisis_id, {})

    # Public Notification
    if severity > 0.5:
        msg = f"URGENT: A {severity_to_word(severity)} {crisis_type} has been reported near {location}. Please avoid the area."
        notifications.append({"target": "public", "message": msg, "channel": "sms, app_push"})

    # Utility Notification (e.g., if fire or flood)
    if crisis_type in ["fire", "flood"] and severity > 0.6:
        msg = f"System Alert: Potential infrastructure risk due to {crisis_type} at {location}. Evaluate grid shutdown protocol."
        notifications.append({"target": "utility_company", "message": msg, "channel": "api_webhook"})

    # Hospital Notification
    if allocated.get("ambulances", 0) > 0:
         msg = f"Medical Alert: Inbound units responding to {crisis_type}. Expect potential casualties from {location}."
         notifications.append({"target": "hospital_network", "message": msg, "channel": "secure_pager"})

    return notifications

def severity_to_word(severity: float) -> str:
    """Helper function to convert float severity to string."""
    if severity > 0.8: return "critical"
    elif severity > 0.5: return "major"
    elif severity > 0.3: return "moderate"
    else: return "minor"


class Orchestrator:
    """
    Top-level controller that drives the agent pipeline.

    Pipeline (rule-11):
        fusion → classifier (FireAgent)
               → allocator  (DecisionAgent -> Resource Allocation)
               → simulator  (AlertAgent -> Action Simulation)
    """

    def __init__(self) -> None:
        """Initialise all sub-agents and the shared trace logger."""
        self.fire: FireAgent = FireAgent()
        self.decision: DecisionAgent = DecisionAgent()
        self.alert: AlertAgent = AlertAgent()
        self.logger: TraceLogger = TraceLogger()
        self.running: bool = False

        # State to track active crises for the allocation step
        self.active_crises = []
        # Mock initial resources available to the system
        self.available_resources = {
            "fire_trucks": 10,
            "ambulances": 15,
            "police": 25,
            "rescue_boats": 5
        }

    async def start(self) -> None:
        """
        Enter the main production loop.

        Polls FireAgent every second. When an alert action is returned,
        forwards the result through DecisionAgent → Allocation → Simulation → Notification
        and logs the outcome.
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
            try:
                # 1. OBSERVE — run fire detection (with safety check)
                result = {}
                if hasattr(self.fire, "run"):
                    result = await self.fire.run({"mode": "continuous"})
                else:
                    pass

                if result and result.get("action") == "alert":

                    # Ensure crisis has an ID for tracking
                    if "id" not in result:
                         import uuid
                         result["id"] = str(uuid.uuid4())

                    # Determine basic details
                    crisis_details = {
                        "id": result["id"],
                        "type": result.get("crisis_type", "fire"), # Default to fire from FireAgent
                        "severity": result.get("severity", 0.8), # Default high if alert triggered
                        "location": result.get("location", "Sector 4") # Mock location
                    }

                    # Add to tracked crises if not present
                    if not any(c.get("id") == crisis_details["id"] for c in self.active_crises):
                         self.active_crises.append(crisis_details)

                    # 2. DECIDE — evaluate severity (existing decision agent)
                    decision = {}
                    if hasattr(self.decision, "run"):
                        decision = await self.decision.run(result)

                    # --- NEW CAPABILITIES INTEGRATION ---

                    # 3. ALLOCATE
                    # Pass a copy of resources so we don't permanently deplete them in this demo loop
                    current_resources = dict(self.available_resources)
                    allocation_plan = allocate_resources(self.active_crises, current_resources)

                    # 4. SIMULATE
                    simulation_results = simulate_action(allocation_plan, crisis_details)

                    # 5. NOTIFY
                    notifications = generate_notifications(crisis_details, allocation_plan, simulation_results)

                    # Package the comprehensive plan
                    comprehensive_plan = {
                        "base_decision": decision,
                        "allocations": allocation_plan.get(crisis_details["id"], {}),
                        "simulation": simulation_results,
                        "notifications": notifications
                    }

                    # --- END NEW CAPABILITIES ---

                    # ACT — dispatch alert to downstream systems (passing the comprehensive plan)
                    if hasattr(self.alert, "run"):
                        await self.alert.run(comprehensive_plan)

                    self.logger.write_trace(
                        agent_name="orchestrator",
                        step_type="DECIDE",
                        reasoning=f"Alert dispatched with full plan: {comprehensive_plan}",
                        confidence_before=0.9,
                        confidence_after=0.95,
                    )

            except Exception as e:
                # Catch any unexpected errors so the server doesn't crash
                print(f"Orchestrator background loop error: {e}")

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

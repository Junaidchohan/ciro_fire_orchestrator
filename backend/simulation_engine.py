import datetime
import logging
from typing import Dict, Any

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

try:
    from services.trace_logger import TraceLogger
except ImportError:
    class TraceLogger:
        def write_trace(self, *args, **kwargs):
            pass

def simulate_action(crisis_type: str, location: str, allocation_plan: Dict[str, Any]) -> Dict[str, Any]:
    """
    Simulates the impact of an allocation plan on a given crisis.

    Args:
        crisis_type: The type of crisis (e.g., 'fire', 'flood').
        location: The location of the crisis.
        allocation_plan: Dictionary of allocated resources.

    Returns:
        Dictionary containing simulation results such as traffic reroute, ETA, and states.
    """
    # Fallback to handle old signature from main.py temporarily if needed
    if isinstance(crisis_type, dict) and isinstance(location, dict) and allocation_plan is None:
        action_plan = crisis_type
        crisis_context = location
        c_type = crisis_context.get("type", "incident")
        loc = crisis_context.get("location", "Unknown")
        alloc = action_plan
        return simulate_action(c_type, loc, alloc)

    crisis_type_lower = crisis_type.lower()
    
    # Initialize defaults
    traffic_reroute = {"affected_roads": [f"{location} Main Road"], "congestion_reduction": "20%"}
    eta_reduction_minutes = 10
    side_effects = f"General traffic delays near {location}"
    before_state = "Incident reported, resources pending"
    after_state = "Resources dispatched, incident under control"

    # Aggressive dispatch for fire
    if "fire" in crisis_type_lower:
        traffic_reroute = {
            "affected_roads": [f"{location} Main", f"{location} Service Road"], 
            "congestion_reduction": "45%"
        }
        eta_reduction_minutes = 12
        side_effects = f"Mild congestion on alternate routes near {location}"
        before_state = "Active blaze spreading. 0% containment. High civilian exposure risk."
        after_state = "Projected containment at 45% within 1 hour. Evacuation initiated."
    # Slower response for flood
    elif "flood" in crisis_type_lower:
        traffic_reroute = {
            "affected_roads": [f"{location} Underpass", f"{location} Low-lying areas"], 
            "congestion_reduction": "15%"
        }
        eta_reduction_minutes = 5
        side_effects = f"Waterlogging on alternate routes near {location}"
        before_state = "Water levels rising. 4 vehicles stranded."
        after_state = "Water rescue deployed. Vehicles expected cleared in 30 mins."
        
    result = {
        "traffic_reroute": traffic_reroute,
        "eta_reduction_minutes": eta_reduction_minutes,
        "side_effects": side_effects,
        "before_state": before_state,
        "after_state": after_state
    }
    
    # Log agent decision using TraceLogger
    try:
        t_logger = TraceLogger()
        t_logger.write_trace(
            agent_name="simulator",
            step_type="SIMULATE",
            reasoning=f"Simulated impact for {crisis_type} at {location}.",
            confidence_before=0.85,
            confidence_after=0.95,
            timestamp=datetime.datetime.now().isoformat()
        )
    except Exception as e:
        logger.error(f"Failed to log trace: {e}")
        
    return result
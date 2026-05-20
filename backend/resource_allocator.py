import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime
import logging

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ResourceAllocator:
    """
    Stateful resource allocator for the CIRO Crisis Response System.
    Maintains an in-memory list of active crises and assigns available units
    based on a strict prioritization algorithm (severity, type, proximity).
    """

    def __init__(self):
        # In-memory store for active crises
        # Schema: {id, type, severity, location, timestamp, resources_needed, resources_allocated}
        self.active_crises: List[Dict[str, Any]] = []

    def _get_travel_time(self, location: str) -> int:
        """Mock function to derive travel time in minutes from a location string."""
        loc = location.lower()
        if "g-10" in loc:
            return 5
        elif "f-11" in loc:
            return 15
        return 10  # Default travel time for unknown locations

    def _get_type_weight(self, crisis_type: str) -> int:
        """Assigns numerical priority weight based on crisis type."""
        c_type = crisis_type.lower()
        if "fire" in c_type:
            return 30
        elif "flood" in c_type:
            return 20
        elif "accident" in c_type:
            return 10
        return 0

    def _calculate_priority(self, crisis: Dict[str, Any]) -> float:
        """
        Calculates the priority score. Higher score = Higher priority.
        Formula: (Severity * 100) + Type Weight - Travel Time Penalty
        """
        severity_score = float(crisis.get("severity", 0.0)) * 100
        type_score = self._get_type_weight(crisis.get("type", "unknown"))
        travel_time_penalty = self._get_travel_time(crisis.get("location", ""))

        return severity_score + type_score - travel_time_penalty

    def _determine_needs(self, crisis: Dict[str, Any]) -> Dict[str, int]:
        """Calculates what resources a crisis actually needs based on type and severity."""
        c_type = crisis.get("type", "unknown").lower()
        severity = float(crisis.get("severity", 0.0))

        needs = {}
        if "fire" in c_type:
            if severity >= 0.8:
                needs = {"fire_trucks": 3, "ambulances": 2, "police": 2}
            else:
                needs = {"fire_trucks": 1, "police": 1}
        elif "flood" in c_type:
            if severity >= 0.8:
                needs = {"rescue_teams": 3, "police": 2, "ambulances": 1}
            else:
                needs = {"rescue_teams": 1, "police": 1}
        elif "accident" in c_type:
            if severity >= 0.8:
                needs = {"ambulances": 3, "police": 2, "fire_trucks": 1}
            else:
                needs = {"ambulances": 1, "police": 1}
        else:
            needs = {"police": 1} # Default fallback

        return needs

    def allocate_resources(self, new_crisis: Optional[Dict[str, Any]], available_units: Dict[str, int]) -> Dict[str, Any]:
        """
        Main allocation logic. Adds the new crisis, calculates needs, sorts the
        global active queue by priority, and greedily assigns available resources.
        """
        # 1. Register new crisis if provided
        if new_crisis:
            # Ensure it's not already tracked to prevent duplicates
            if not any(c["id"] == new_crisis["id"] for c in self.active_crises):
                crisis_record = new_crisis.copy()
                if "timestamp" not in crisis_record:
                    crisis_record["timestamp"] = datetime.now().isoformat()

                crisis_record["resources_needed"] = self._determine_needs(crisis_record)
                crisis_record["resources_allocated"] = crisis_record.get("resources_allocated", {})
                self.active_crises.append(crisis_record)
                logger.info(f"Registered new crisis {crisis_record['id']} ({crisis_record['type']})")

        # 2. Sort all active crises by calculated priority (highest first)
        sorted_crises = sorted(self.active_crises, key=self._calculate_priority, reverse=True)

        allocation_plan = {}
        waiting_list = []

        # 3. Iterate and Allocate
        for crisis in sorted_crises:
            c_id = crisis["id"]
            allocation_plan[c_id] = {"resources": {}}

            needs = crisis.get("resources_needed", {})
            allocated = crisis.get("resources_allocated", {})

            is_fully_met = True

            for res_type, required_amount in needs.items():
                current_amount = allocated.get(res_type, 0)
                shortfall = required_amount - current_amount

                if shortfall > 0:
                    available = available_units.get(res_type, 0)
                    grant = min(shortfall, available)

                    if grant > 0:
                        # Update local state
                        allocated[res_type] = current_amount + grant
                        # Update response plan
                        allocation_plan[c_id]["resources"][res_type] = grant
                        # Deduct from global available pool
                        available_units[res_type] -= grant

                    # Check if we still have a shortfall after this pass
                    if allocated.get(res_type, 0) < required_amount:
                        is_fully_met = False

            if not is_fully_met:
                waiting_list.append(c_id)

        return {
            "allocation_plan": allocation_plan,
            "waiting_list": waiting_list,
            "remaining_units": available_units
        }

    def resolve_crisis(self, crisis_id: str) -> Dict[str, Any]:
        """
        Removes a crisis from the active list (e.g., when resolved or a false alarm).
        Returns the resources that should be added back to the available pool.
        """
        crisis_to_remove = next((c for c in self.active_crises if c["id"] == crisis_id), None)

        if not crisis_to_remove:
            logger.warning(f"Attempted to resolve unknown crisis ID: {crisis_id}")
            return {"status": "error", "message": "Crisis not found.", "freed_resources": {}}

        freed_resources = crisis_to_remove.get("resources_allocated", {})
        self.active_crises.remove(crisis_to_remove)
        logger.info(f"Resolved crisis {crisis_id}. Freed resources: {freed_resources}")

        return {
            "status": "success",
            "message": f"Crisis {crisis_id} resolved.",
            "freed_resources": freed_resources
        }


# --- Module-Level Singleton ---
allocator_instance = ResourceAllocator()

# Wrapper functions for easy importing in main.py
def allocate_resources(new_crisis: Optional[Dict[str, Any]], available_units: Dict[str, int]) -> Dict[str, Any]:
    return allocator_instance.allocate_resources(new_crisis, available_units)

def resolve_crisis(crisis_id: str) -> Dict[str, Any]:
    return allocator_instance.resolve_crisis(crisis_id)

def get_active_crises() -> List[Dict[str, Any]]:
    return allocator_instance.active_crises


# ==========================================
# TEST EXECUTION GUARD
# ==========================================
if __name__ == "__main__":
    import json
    print("=== Testing Resource Allocator ===")

    # 1. Define pool
    pool = {"ambulances": 3, "police": 2, "fire_trucks": 1, "rescue_teams": 2}
    print(f"Initial Pool: {pool}\n")

    # 2. Add High Priority Fire in G-10 (Close, High Severity)
    crisis_1 = {
        "id": "c1",
        "type": "fire",
        "severity": 0.9,
        "location": "G-10, Islamabad"
    }

    # 3. Add Lower Priority Flood in F-11 (Farther, Lower Severity)
    crisis_2 = {
        "id": "c2",
        "type": "flood",
        "severity": 0.6,
        "location": "F-11, Islamabad"
    }

    # Run allocation for first crisis
    res_1 = allocate_resources(crisis_1, pool)
    print(f"After Crisis 1 (Fire, High Priority):\n{json.dumps(res_1, indent=2)}\n")

    # Run allocation for second crisis (should hit the waiting list due to depleted pool)
    res_2 = allocate_resources(crisis_2, pool)
    print(f"After Crisis 2 (Flood, Lower Priority):\n{json.dumps(res_2, indent=2)}\n")

    # 4. Resolve Crisis 1 (False alarm or handled)
    resolution = resolve_crisis("c1")
    print(f"Resolving Crisis 1:\n{json.dumps(resolution, indent=2)}\n")

    # Simulate returning units to the pool in a real app
    for k, v in resolution["freed_resources"].items():
        pool[k] = pool.get(k, 0) + v

    print(f"Restored Pool: {pool}")

    # 5. Re-run allocation to let Crisis 2 claim the newly freed resources
    res_3 = allocate_resources(None, pool)
    print(f"\nRe-allocating for Waiting List:\n{json.dumps(res_3, indent=2)}")
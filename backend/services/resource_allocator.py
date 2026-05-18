"""
resource_allocator.py
---------------------
Service that manages emergency resource inventory and allocates assets
based on crisis type and severity for the CIRO Crisis Response System.
"""

import time
from typing import Dict, Any, List


class ResourceAllocator:
    """
    Manages the available pool of emergency resources and determines
    which units to deploy for a given crisis scenario.

    Resources are tracked as a shared mutable dict so subsequent
    allocations reflect real-time availability throughout a session.
    """

    # Crisis → preferred deployment order (most critical first)
    _ALLOCATION_MAP: Dict[str, List[str]] = {
        "fire":     ["fire_truck", "ambulance", "police"],
        "flood":    ["rescue_team", "ambulance", "police"],
        "heatwave": ["ambulance", "rescue_team"],
    }

    # Severity multiplier on unit count: high=2, medium=1, low=1
    _SEVERITY_COUNT: Dict[str, int] = {
        "high":   2,
        "medium": 1,
        "low":    1,
        "none":   0,
    }

    def __init__(self) -> None:
        """
        Initialise resource inventory with default fleet sizes and
        average response times (in minutes) for each unit type.
        """
        # mock: initial fleet state — 5 ambulances, 10 police, etc.
        self.resources: Dict[str, Dict[str, Any]] = {
            "ambulance":   {"count": 5,  "available": 5,  "response_time_min": 8},
            "police":      {"count": 10, "available": 10, "response_time_min": 5},
            "rescue_team": {"count": 3,  "available": 3,  "response_time_min": 12},
            "fire_truck":  {"count": 4,  "available": 4,  "response_time_min": 6},
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def allocate(
        self,
        crisis_type: str,
        severity: str,
        location: str,
    ) -> Dict[str, Any]:
        """
        Determine which resources to deploy and update availability counts.

        Args:
            crisis_type (str): Type of crisis ('fire' | 'flood' | 'heatwave').
            severity    (str): Severity tier ('high' | 'medium' | 'low' | 'none').
            location    (str): Free-text location label for audit logging.

        Returns:
            Dict[str, Any]: Structured allocation result containing:
                - allocated_resources: list of unit types dispatched.
                - units_dispatched:    number of units per type.
                - estimated_arrival_min: weighted ETA in minutes.
                - coverage_score:      0-1 readiness score.
                - resource_status:     post-allocation inventory snapshot.
                - location:            echoed location string.
                - timestamp:           Unix epoch of allocation.
        """
        needed_units = self._SEVERITY_COUNT.get(severity, 1)

        # If severity is 'none', return early — no deployment warranted
        if needed_units == 0:
            return {
                "allocated_resources": [],
                "units_dispatched": {},
                "estimated_arrival_min": 0,
                "coverage_score": 1.0,
                "resource_status": self.resources,
                "location": location,
                "timestamp": time.time(),
            }

        preferred = self._ALLOCATION_MAP.get(crisis_type, ["ambulance"])
        allocated: List[str] = []
        dispatched: Dict[str, int] = {}

        for unit_type in preferred:
            info = self.resources.get(unit_type, {})
            available = info.get("available", 0)
            if available > 0:
                # Deploy `needed_units` or however many are left
                deploy = min(needed_units, available)
                self.resources[unit_type]["available"] -= deploy
                allocated.append(unit_type)
                dispatched[unit_type] = deploy

        return {
            "allocated_resources": allocated,
            "units_dispatched": dispatched,
            "estimated_arrival_min": self._calculate_eta(allocated),
            "coverage_score": self._coverage_score(allocated, preferred),
            "resource_status": self.resources,
            "location": location,
            "timestamp": time.time(),
        }

    def release(self, unit_type: str, units: int = 1) -> bool:
        """
        Return previously dispatched units back to the available pool.

        Args:
            unit_type (str): The resource type to release.
            units     (int): Number of units to return (default 1).

        Returns:
            bool: True if release succeeded, False if unit_type unknown.
        """
        if unit_type not in self.resources:
            return False
        info = self.resources[unit_type]
        info["available"] = min(info["count"], info["available"] + units)
        return True

    def status(self) -> Dict[str, Any]:
        """
        Return a read-only snapshot of the current resource pool.

        Returns:
            Dict[str, Any]: Current availability and capacity per unit type.
        """
        return {k: dict(v) for k, v in self.resources.items()}

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _calculate_eta(self, unit_types: List[str]) -> float:
        """
        Compute the worst-case (slowest unit) estimated arrival time.

        Args:
            unit_types (List[str]): Unit types being dispatched.

        Returns:
            float: Maximum response_time_min across all dispatched units,
                   or 0.0 if the list is empty.
        """
        if not unit_types:
            return 0.0
        times = [
            self.resources[u]["response_time_min"]
            for u in unit_types
            if u in self.resources
        ]
        return float(max(times)) if times else 0.0

    def _coverage_score(
        self,
        allocated: List[str],
        preferred: List[str],
    ) -> float:
        """
        Calculate a 0–1 coverage score based on how many preferred unit
        types were actually available for dispatch.

        Args:
            allocated (List[str]): Unit types actually dispatched.
            preferred (List[str]): Full list of ideal unit types.

        Returns:
            float: Ratio of filled slots to total preferred slots.
        """
        if not preferred:
            return 1.0
        return round(len(allocated) / len(preferred), 2)


# Module-level singleton — import `allocator` directly elsewhere
allocator = ResourceAllocator()

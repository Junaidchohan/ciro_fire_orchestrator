import logging
from typing import Dict, Any, List

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class NotificationGenerator:
    """
    Generates targeted, dynamic alerts for various stakeholders
    (Public, Hospitals, Utilities, Command Center, Media) based on the
    crisis context, resource allocations, and simulation forecasts.
    """

    def generate_notifications(
        self,
        crisis: Dict[str, Any],
        simulation: Dict[str, Any],
        allocation: Dict[str, Any]
    ) -> List[Dict[str, Any]]:

        logger.info(f"Generating notifications for crisis ID: {crisis.get('id', 'UNKNOWN')}")

        notifications = []

        # Extract context
        c_id = crisis.get("id", "UNKNOWN-ID")
        c_type = str(crisis.get("type", "incident")).upper()
        severity = float(crisis.get("severity", 0.5))
        location = crisis.get("location", "an unspecified location")

        # Extract simulation stats
        traffic_sim = simulation.get("traffic_reroute", {})
        congestion_red = traffic_sim.get("estimated_congestion_reduction", "unknown%")

        # Format allocation string
        alloc_str = ", ".join([f"{v} {k.replace('_', ' ')}" for k, v in allocation.items()])
        if not alloc_str:
            alloc_str = "No specific resources allocated yet"

        # 1. PUBLIC NOTIFICATION
        public_urgency = "high" if severity >= 0.7 else "medium"
        if c_type == "FIRE":
            public_msg = f"⚠️ URGENT: {c_type} reported in {location}. Avoid the area. Keep windows closed due to smoke. Follow emergency routes."
        elif c_type == "FLOOD":
            public_msg = f"⚠️ URGENT: {c_type} warning in {location}. Do not drive through standing water. Evacuate low-lying zones immediately."
        else:
            public_msg = f"⚠️ ALERT: {c_type} incident reported in {location}. Emergency crews are responding. Avoid the area."

        notifications.append({
            "stakeholder": "public",
            "channel": "emergency_alert_system",
            "message": public_msg,
            "urgency": public_urgency
        })

        # 2. HOSPITAL NOTIFICATION (Only if severity is high or ambulances dispatched)
        ambulances = allocation.get("ambulances", 0)
        if severity >= 0.6 or ambulances > 0:
            est_casualties = int(severity * 25) # Mock calculation
            color_code = "RED" if severity >= 0.8 else "YELLOW"
            hospital_msg = (f"CODE {color_code}: {c_type} crisis in {location}. "
                            f"Expect {est_casualties - 5}-{est_casualties + 5} inbound casualties over the next 2 hours. "
                            f"{ambulances} ambulances currently dispatched. Prepare ER and trauma teams.")
            notifications.append({
                "stakeholder": "hospital",
                "channel": "dashboard",
                "message": hospital_msg,
                "urgency": "high" if severity >= 0.8 else "medium"
            })

        # 3. UTILITY COMPANY NOTIFICATION (For infrastructure-threatening crises)
        if c_type in ["FIRE", "FLOOD"]:
            utility_urgency = "high" if severity >= 0.75 else "medium"
            if c_type == "FIRE":
                util_msg = f"GAS SHUTOFF ALERT: High-severity fire near {location}. Pre-emptively shut off gas mains in adjacent sectors to prevent secondary explosions."
            else:
                util_msg = f"WATER/POWER ALERT: Severe flooding in {location}. Shut off electrical grid to ground-level transformers and monitor water main contamination."

            notifications.append({
                "stakeholder": "utility_company",
                "channel": "email",
                "message": util_msg,
                "urgency": utility_urgency
            })

        # 4. COMMAND CENTER NOTIFICATION (Always generated)
        cmd_msg = (f"Crisis ID #{c_id.split('-')[0].upper()}: {c_type} at {location}. "
                   f"Resources allocated: {alloc_str}. "
                   f"Simulation forecasts a {congestion_red} congestion reduction.")
        notifications.append({
            "stakeholder": "command_center",
            "channel": "dashboard",
            "message": cmd_msg,
            "urgency": "high" if severity >= 0.8 else "medium"
        })

        # 5. MEDIA / PRESS NOTIFICATION (For major incidents)
        if severity >= 0.7:
            media_msg = (f"PRESS ADVISORY: City authorities are actively responding to a major {c_type} incident at {location}. "
                         f"Citizens are advised to use alternate routes. Official statement to follow.")
            notifications.append({
                "stakeholder": "media",
                "channel": "email",
                "message": media_msg,
                "urgency": "medium"
            })

        return notifications


# --- Module-Level Singleton ---
notifier_instance = NotificationGenerator()

# Wrapper function for easy importing in main.py
def generate_notifications(
    crisis: Dict[str, Any],
    allocation: Dict[str, Any],
    simulation: Dict[str, Any]
) -> List[Dict[str, Any]]:
    return notifier_instance.generate_notifications(crisis, simulation, allocation)


# ==========================================
# TEST EXECUTION GUARD
# ==========================================
if __name__ == "__main__":
    import json
    print("=== Testing Notification Generator ===")

    mock_crisis = {
        "id": "fld-8842-x",
        "type": "flood",
        "severity": 0.85,
        "location": "G-10, Islamabad"
    }

    mock_allocation = {
        "ambulances": 2,
        "rescue_teams": 3,
        "police": 4
    }

    mock_simulation = {
        "traffic_reroute": {
            "estimated_congestion_reduction": "40%"
        }
    }

    results = generate_notifications(mock_crisis, mock_allocation, mock_simulation)

    print("\nGenerated Notifications:")
    print(json.dumps(results, indent=4))
import logging
from typing import Dict, Any, List
from services.trace_logger import TraceLogger

logger = logging.getLogger(__name__)

def generate_notifications(crisis_type: str, severity: float, location: str, allocation_plan: Dict[str, int]) -> List[Dict[str, Any]]:
    """
    Generates targeted, dynamic alerts for various stakeholders
    (Public, Hospital, Utility Company, and Command Centre) based on the
    crisis context and resource allocations.
    """
    trace_logger = TraceLogger()
    notifications = []
    
    # Format allocation string for command centre
    alloc_str = ", ".join([f"{v} {k.replace('_', ' ')}" for k, v in allocation_plan.items()])
    if not alloc_str:
        alloc_str = "None"

    # Convert severity to float in case it's a string
    try:
        sev_val = float(severity)
    except ValueError:
        sev_val = 0.5

    # 1. Public Notification
    if sev_val >= 0.7:
        public_msg = f"⚠️ URGENT: {crisis_type.capitalize()} at {location}. Avoid area. Use alternate routes."
        public_urgency = "high"
    else:
        public_msg = f"⚠️ ALERT: {crisis_type.capitalize()} reported at {location}. Please be cautious."
        public_urgency = "medium"

    notifications.append({
        "stakeholder": "public",
        "channel": "sms",
        "message": public_msg,
        "urgency": public_urgency
    })

    # 2. Hospital Notification
    ambulances = allocation_plan.get("ambulances", 0)
    if sev_val >= 0.6 or ambulances > 0:
        est_cases_min = max(1, int(sev_val * 10))
        est_cases_max = est_cases_min + 5
        color_code = "RED" if sev_val >= 0.8 else "YELLOW"
        hospital_msg = f"CODE {color_code}: Expect {est_cases_min}-{est_cases_max} cases from {crisis_type} at {location}. Prepare ER."
        notifications.append({
            "stakeholder": "hospital",
            "channel": "dashboard",
            "message": hospital_msg,
            "urgency": "high" if sev_val >= 0.8 else "medium"
        })

    # 3. Utility Company Notification
    if str(crisis_type).lower() in ["fire", "flood"]:
        if str(crisis_type).lower() == "fire":
            utility_msg = f"Check water pressure and power lines near {location}."
        else:
            utility_msg = f"Monitor drainage and electrical transformers near {location}."
            
        notifications.append({
            "stakeholder": "utility",
            "channel": "email",
            "message": utility_msg,
            "urgency": "high" if sev_val >= 0.75 else "medium"
        })

    # 4. Command Centre Notification
    cmd_msg = f"Crisis ID: ... Resources allocated: {alloc_str}."
    notifications.append({
        "stakeholder": "command_centre",
        "channel": "dashboard",
        "message": cmd_msg,
        "urgency": "high" if sev_val >= 0.8 else "medium"
    })
    
    # Write trace log
    trace_logger.write_trace(
        agent_name="NotificationGenerator",
        step_type="generate_notifications",
        reasoning=f"Generated {len(notifications)} notifications for {crisis_type} at {location} with severity {sev_val}",
        confidence_before=1.0,
        confidence_after=1.0,
        inputs={"crisis_type": crisis_type, "severity": sev_val, "location": location, "allocation_plan": allocation_plan},
        output={"notifications_count": len(notifications)}
    )

    return notifications
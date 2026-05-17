"""
Utility script to generate sample trace logs for the Fire Crisis Response System.
Creates a mock session JSON file containing realistic traces from different agents.
"""

import os
import sys
from datetime import datetime, timedelta
from typing import List, Dict, Any

# Ensure backend root is in sys.path for importing services
current_dir = os.path.dirname(os.path.abspath(__file__))
backend_root = os.path.dirname(current_dir)
if backend_root not in sys.path:
    sys.path.append(backend_root)

from services.trace_logger import TraceLogger


def generate_sample_traces() -> str:
    """
    Generates a sample traces file with mock agent logs.
    
    Creates a file named logs/demo_runs/traces_sample_TIMESTAMP.json with 6
    realistic traces tracking the flow of the fire crisis orchestration pipeline.
    
    Returns:
        str: The path to the created sample trace log file.
    """
    # mock: Sample trace entries for demonstration of the fire crisis agent orchestration flow
    
    # Establish workspace and log directories relative to backend root
    workspace_root = os.path.dirname(backend_root)
    log_dir = os.path.join(workspace_root, "logs", "demo_runs")
    
    # Format session timestamp
    timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    session_id = f"sample_{timestamp_str}"
    
    # Initialize the TraceLogger with the correct directory and session ID
    logger = TraceLogger(log_dir=log_dir, session_id=session_id)
    
    base_time = datetime.now() - timedelta(minutes=15)
    
    # Realistic agent execution sequence matching fusion -> classification -> allocation -> simulation
    sample_data: List[Dict[str, Any]] = [
        {
            "agent_name": "yolo_agent",
            "step_type": "OBSERVE",
            "reasoning": "Scanning real-time forest watch CCTV feeds. Detected heat signatures and high smoke column index in Sector 4B.",
            "confidence_before": 0.55,
            "confidence_after": 0.89,
            "inputs": {"camera_id": "CCTV-Sector-4B", "stream_active": True},
            "output": {"anomaly_detected": True, "bounding_boxes": [{"class": "smoke", "confidence": 0.89}]},
            "duration_ms": 1450.0,
            "time_offset_seconds": 0
        },
        {
            "agent_name": "fire_agent",
            "step_type": "ANALYZE",
            "reasoning": "Fusing YOLO detection with satellite thermal sensors and local weather station data. Confirmed low-humidity high-wind environment.",
            "confidence_before": 0.80,
            "confidence_after": 0.95,
            "inputs": {"cctv_smoke_detected": True, "satellite_temp_c": 312.5, "wind_speed_kmh": 22.0},
            "output": {"fire_risk_score": 0.95, "confirmed_fire": True},
            "duration_ms": 820.0,
            "time_offset_seconds": 90
        },
        {
            "agent_name": "decision_agent",
            "step_type": "ANALYZE",
            "reasoning": "Classifying fire severity and threat vectors. Identified a nearby high-density urban fringe within 2 kilometers.",
            "confidence_before": 0.70,
            "confidence_after": 0.91,
            "inputs": {"confirmed_fire": True, "fuel_type": "pine_dry", "proximity_to_assets_km": 1.8},
            "output": {"threat_level": "CRITICAL", "evacuation_recommended": True},
            "duration_ms": 640.0,
            "time_offset_seconds": 180
        },
        {
            "agent_name": "decision_agent",
            "step_type": "DECIDE",
            "reasoning": "Determining response resources and optimal deployment. Selected water-bombing helicopter and local wildland taskforce.",
            "confidence_before": 0.75,
            "confidence_after": 0.94,
            "inputs": {"threat_level": "CRITICAL", "available_assets": ["station_3_engine", "chopper_1", "station_5_engine"]},
            "output": {"selected_action": "DISPATCH", "assets_to_dispatch": ["chopper_1", "station_3_engine"]},
            "duration_ms": 1100.0,
            "time_offset_seconds": 240
        },
        {
            "agent_name": "decision_agent",
            "step_type": "ACT",
            "reasoning": "Transmitting dispatch orders to the emergency responder dispatch API and triggering local warnings.",
            "confidence_before": 0.90,
            "confidence_after": 0.98,
            "inputs": {"dispatch_payload": {"assets": ["chopper_1", "station_3_engine"], "destination": "Sector 4B"}},
            "output": {"dispatch_status": "SENT", "incident_id": "INC-2026-0042"},
            "duration_ms": 450.0,
            "time_offset_seconds": 270
        },
        {
            "agent_name": "decision_agent",
            "step_type": "EVALUATE",
            "reasoning": "Running predictive forest fire expansion model to project spread over the next two hours with resource suppression.",
            "confidence_before": 0.85,
            "confidence_after": 0.97,
            "inputs": {"incident_id": "INC-2026-0042", "active_suppression": True},
            "output": {"containment_probability": 0.92, "estimated_control_time_hours": 3.5},
            "duration_ms": 2300.0,
            "time_offset_seconds": 360
        }
    ]
    
    # Write each trace entry using the logger
    for entry in sample_data:
        # Calculate staggered timestamp
        offset = entry["time_offset_seconds"]
        entry_time = base_time + timedelta(seconds=offset)
        iso_timestamp = entry_time.isoformat()
        
        logger.write_trace(
            agent_name=entry["agent_name"],
            step_type=entry["step_type"],
            reasoning=entry["reasoning"],
            confidence_before=entry["confidence_before"],
            confidence_after=entry["confidence_after"],
            inputs=entry["inputs"],
            output=entry["output"],
            duration_ms=entry["duration_ms"],
            timestamp=iso_timestamp
        )
        
    print(f"Successfully generated sample trace log file: {logger.log_file}")
    return logger.log_file


if __name__ == "__main__":
    generate_sample_traces()

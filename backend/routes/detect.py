"""
detect.py
---------
FastAPI router exposing multi-hazard detection (fire, flood, heatwave)
via the Orchestrator and CrisisClassifier agents, plus continuous
production loop lifecycle management.
"""

import os
from typing import Dict, Any, Optional
from fastapi import APIRouter, File, UploadFile, BackgroundTasks, Body, Form
import cv2
import tempfile
from agents.orchestrator import orchestrator
from agents.decision_agent import agent as decision_agent
from agents.crisis_classifier import classifier

# Initialize the router without a hardcoded /detect prefix to perfectly match
# the custom @router.post("/detect") paths.
router = APIRouter(tags=["Detection"])


@router.post("/detect")
async def detect(
    image: UploadFile = File(...),
    background: BackgroundTasks = None,
) -> Dict[str, Any]:
    """
    Accepts an uploaded image file, saves it locally, and executes the
    FireAgent OODA loop pipeline via the Orchestrator.

    Args:
        image (UploadFile): The image file uploaded by the client.
        background (BackgroundTasks): FastAPI background task manager.

    Returns:
        Dict[str, Any]: A summary of the fire agent's detection, confidence, and agent trace.
    """
    # Save the uploaded file locally so it exists on disk for YOLO/opencv
    contents = await image.read()
    filename = image.filename or "temp_image.jpg"
    with open(filename, "wb") as f:
        f.write(contents)

    fire_result = {}
    try:
        # ✅ SAFETY CHECK: Prevent crash if 'run' method does not exist
        if hasattr(orchestrator.fire, "run"):
            fire_result = await orchestrator.fire.run({"image": filename})
        else:
            print("Warning: FireAgent missing 'run'. Using safe fallback.")
            fire_result = {"action": "monitor", "severity": "none"}
    except Exception as e:
        print(f"FireAgent execution error: {e}")
        fire_result = {"action": "monitor", "severity": "none"}
    finally:
        # Clean up the file after agent execution to prevent filesystem bloat
        if os.path.exists(filename):
            try:
                os.remove(filename)
            except Exception:
                pass

    # Build synthetic YOLO-compatible result from FireAgent output
    yolo_result: Dict[str, Any] = {
        "detected": fire_result.get("action") in ("alert", "evacuate"),
        "confidence": 0.9 if fire_result.get("severity") == "high" else 0.6,
        "severity": fire_result.get("severity", "none"),
    }

    # ✅ SAFETY CHECK: Wrap the decision agent so it doesn't crash on invalid data
    try:
        decision = decision_agent.decide(
            detection_result=yolo_result,
            weather_data={},
            social_data={},
        )
    except Exception as e:
        print(f"Decision agent error: {e}")
        decision = {
            "confidence": yolo_result["confidence"],
            "crisis_type": "fire",
            "severity": yolo_result["severity"],
            "action": "MONITOR" if not yolo_result["detected"] else "WARNING",
            "recommended_action": "Safe Fallback: Monitor area closely.",
            "reasoning": f"Fallback triggered due to agent error.",
            "all_classifiers": []
        }

    return {
        "detected": yolo_result.get("detected", False),
        "confidence": decision.get("confidence", 0.0),
        "crisis_type": decision.get("crisis_type", "unknown"),
        "severity": decision.get("severity", "none"),
        "action": decision.get("action", "MONITOR"),
        "recommended_action": decision.get("recommended_action", "Monitor"),
        "reasoning": decision.get("reasoning", "No reasoning available"),
        "agent_trace": fire_result,
        "all_classifiers": decision.get("all_classifiers", []),
    }


@router.post("/detect_video")
async def detect_video(
    video: UploadFile = File(...),
    social_text: Optional[str] = Form(None),
    lat: Optional[str] = Form("33.6844"),
    lon: Optional[str] = Form("73.0479"),
    test_mode: Optional[str] = Form("false"),
) -> Dict[str, Any]:
    """
    Accepts an uploaded video file, samples every 30th frame, and runs detection.
    """
    contents = await video.read()
    filename = video.filename or "temp_video.mp4"
    with open(filename, "wb") as f:
        f.write(contents)

    cap = cv2.VideoCapture(filename)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_interval = 30
    frame_count = 0
    
    frame_results = []
    overall_detected = False
    max_confidence = 0.0
    highest_severity = "none"
    last_decision = {}
    last_agent_trace = {}

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
            
        if frame_count % frame_interval == 0:
            temp_frame_path = f"temp_frame_{frame_count}.jpg"
            cv2.imwrite(temp_frame_path, frame)
            
            timestamp = frame_count / fps
            
            try:
                if hasattr(orchestrator.fire, "run"):
                    fire_result = await orchestrator.fire.run({"image": temp_frame_path})
                else:
                    fire_result = {"action": "monitor", "severity": "none"}
            except Exception as e:
                fire_result = {"action": "monitor", "severity": "none"}
                
            if os.path.exists(temp_frame_path):
                os.remove(temp_frame_path)
                
            is_detected = fire_result.get("action") in ("alert", "evacuate")
            conf = 0.9 if fire_result.get("severity") == "high" else 0.6
            sev = fire_result.get("severity", "none")
            
            if is_detected:
                overall_detected = True
            if conf > max_confidence:
                max_confidence = conf
            if sev == "high" or (sev == "medium" and highest_severity != "high"):
                highest_severity = sev
                
            if is_detected:
                frame_results.append({
                    "timestamp": round(timestamp, 2),
                    "confidence": conf,
                    "boxes": [], # simplified
                })
                
            last_agent_trace = fire_result

        frame_count += 1

    cap.release()
    if os.path.exists(filename):
        os.remove(filename)
        
    yolo_result = {
        "detected": overall_detected,
        "confidence": max_confidence,
        "severity": highest_severity,
    }
    
    try:
        decision = decision_agent.decide(
            detection_result=yolo_result,
            weather_data={},
            social_data={"text": social_text} if social_text else {},
        )
    except Exception as e:
        decision = {
            "confidence": yolo_result["confidence"],
            "crisis_type": "fire",
            "severity": yolo_result["severity"],
            "action": "MONITOR" if not yolo_result["detected"] else "WARNING",
            "recommended_action": "Safe Fallback",
            "reasoning": f"Fallback triggered",
            "all_classifiers": []
        }

    return {
        "detected": overall_detected,
        "confidence": decision.get("confidence", max_confidence),
        "crisis_type": decision.get("crisis_type", "unknown"),
        "severity": decision.get("severity", "none"),
        "action": decision.get("action", "MONITOR"),
        "recommended_action": decision.get("recommended_action", "Monitor"),
        "reasoning": decision.get("reasoning", "No reasoning available"),
        "agent_trace": last_agent_trace,
        "all_classifiers": decision.get("all_classifiers", []),
        "frame_results": frame_results,
        "crisis_id": f"vid_crisis_{int(max_confidence * 100)}",
        "allocation_plan": decision.get("allocation_plan", {}),
        "simulation": decision.get("simulation", {"eta_reduction_minutes": 5, "traffic_reroute": True, "side_effects": "None"}),
        "notifications": decision.get("notifications", [{"target": "public", "message": "Fire detected in video"}] if overall_detected else [])
    }



@router.post("/classify")
async def classify_crisis(
    weather_data: Dict[str, Any] = Body(default={}, embed=False),
    social_data: Dict[str, Any] = Body(default={}, embed=False),
) -> Dict[str, Any]:
    """
    Classify a crisis from weather and social signals without an image upload.
    Accepts a JSON body with optional 'weather_data' and 'social_data' keys.

    Example body::

        {
            "weather_data": {"rainfall_mm": 30, "temperature": 42},
            "social_data":  {"text": "flooding reported near river bank"}
        }

    Returns:
        Dict[str, Any]: Multi-hazard classification with crisis_type and decision.
    """
    try:
        decision = decision_agent.decide(
            detection_result={"detected": False, "confidence": 0.0},
            weather_data=weather_data,
            social_data=social_data,
        )
        return decision
    except Exception as e:
        print(f"Classification error: {e}")
        return {"action": "MONITOR", "reasoning": "Fallback due to error"}


@router.post("/production/start")
async def start_production(background: BackgroundTasks) -> Dict[str, str]:
    """
    Start the continuous production orchestration loop in the background.

    Args:
        background (BackgroundTasks): FastAPI background task manager.

    Returns:
        Dict[str, str]: Status message confirming production loop has started.
    """
    background.add_task(orchestrator.start)
    return {"status": "production_started"}


@router.post("/production/stop")
async def stop_production() -> Dict[str, str]:
    """
    Gracefully stop the continuous production orchestration loop.

    Returns:
        Dict[str, str]: Status message confirming production loop has stopped.
    """
    await orchestrator.stop()
    return {"status": "production_stopped"}
"""
detect.py
---------
FastAPI router exposing multi-hazard detection (fire, flood, heatwave)
via the Orchestrator and CrisisClassifier agents, plus continuous
production loop lifecycle management.
"""

import os
from typing import Dict, Any, Optional
from fastapi import APIRouter, File, UploadFile, BackgroundTasks, Body
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
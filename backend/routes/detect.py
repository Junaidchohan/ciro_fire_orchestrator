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

    try:
        # Run FireAgent OODA loop via orchestrator
        fire_result = await orchestrator.fire.run({"image": filename})
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

    # Run full multi-hazard decision (fire only when coming from image upload;
    # weather/social data not available here — pass empty dicts)
    decision = decision_agent.decide(
        detection_result=yolo_result,
        weather_data={},
        social_data={},
    )

    return {
        "detected": yolo_result["detected"],
        "confidence": decision["confidence"],
        "crisis_type": decision["crisis_type"],
        "severity": decision["severity"],
        "action": decision["action"],
        "recommendation": decision["recommendation"],
        "reasoning": decision["reasoning"],
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
    decision = decision_agent.decide(
        detection_result={"detected": False, "confidence": 0.0},
        weather_data=weather_data,
        social_data=social_data,
    )
    return decision


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

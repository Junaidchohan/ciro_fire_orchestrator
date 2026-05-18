"""
detect.py
---------
FastAPI router exposing fire/smoke detection via the Orchestrator agent
and managing continuous production loop lifecycle.
"""

import os
from typing import Dict, Any
from fastapi import APIRouter, File, UploadFile, BackgroundTasks
from agents.orchestrator import orchestrator

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
        # Run agent asynchronously
        result = await orchestrator.fire.run({"image": filename})
    finally:
        # Clean up the file after agent execution to prevent filesystem bloat
        if os.path.exists(filename):
            try:
                os.remove(filename)
            except Exception:
                pass

    return {
        "detected": result.get("action") == "alert",
        "confidence": 0.9 if result.get("severity") == "high" else 0.6,
        "agent_trace": result,
    }


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

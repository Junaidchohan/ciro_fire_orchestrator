from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, List, Any
import json, os, glob

from routes.detect import router as detect_router
from websocket_endpoint import router as ws_router
from services.yolo_detector import detector
from agents.decision_agent import agent

# Initialize FastAPI Application
app = FastAPI(
    title="CIRO Fire Orchestrator API",
    description="Backend coordinator for the Fire Crisis Response System",
    version="1.0.0"
)

# Configure Cross-Origin Resource Sharing (CORS)
# Allows the Flutter web/mobile client to communicate with the FastAPI server during local development.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── routers ──────────────────────────────────────────────────────────────────
# /detect           – POST image → YOLO → DecisionAgent pipeline
# /detect/decision  – POST detection JSON → DecisionAgent pipeline only
app.include_router(detect_router)
app.include_router(ws_router)


@app.get("/health")
async def health_check() -> Dict[str, str]:
    """
    Health check endpoint to verify that the backend API is up and running.

    Returns:
        Dict[str, str]: A dictionary with key 'status' indicating service health.
    """
    return {"status": "ok"}


@app.get("/traces")
async def get_traces() -> List[Any]:
    """
    Reads all trace JSON files from the logs/demo_runs directory at the workspace root,
    sorted by their timestamp in the filename (descending),
    and returns a combined JSON array of all traces.

    Returns:
        List[Any]: Combined list of all parsed traces.
    """
    current_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_root = os.path.abspath(os.path.join(current_dir, ".."))
    log_dir = os.path.join(workspace_root, "logs", "demo_runs")

    search_pattern = os.path.join(log_dir, "*.json")
    file_paths = glob.glob(search_pattern)

    # Sorting in descending alphabetical order sorts the timestamped names from newest to oldest
    file_paths.sort(reverse=True)

    all_traces: List[Any] = []
    for file_path in file_paths:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    all_traces.extend(data)
                else:
                    all_traces.append(data)
        except Exception as e:
            print(f"Error reading trace file {file_path}: {e}")

    return all_traces


@app.post("/detect")
async def detect(image: UploadFile = File(...)) -> Dict[str, Any]:
    """
    Accepts an uploaded image file, saves it temporarily, and runs the YOLO
    fire/smoke detector and DecisionAgent pipeline.

    Args:
        image (UploadFile): The uploaded image file.

    Returns:
        Dict[str, Any]: Detection result and agent decision.
    """
    contents = await image.read()
    temp_filename = image.filename or "temp_image.jpg"
    with open(temp_filename, "wb") as f:
        f.write(contents)

    try:
        result = detector.detect_fire(temp_filename)
        decision = agent.decide(result)
    finally:
        if os.path.exists(temp_filename):
            try:
                os.remove(temp_filename)
            except Exception:
                pass

    return {
        "detected": result['detected'],
        "confidence": result['confidence'],
        "decision": decision
    }

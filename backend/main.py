from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Any, Dict, List, Optional
import asyncio, json, os, glob

from routes.detect import router as detect_router
from routes.allocate import router as allocate_router
from routes.signals import router as signals_router
from websocket_endpoint import router as ws_router
from services.yolo_detector import detector
from services.action_simulator import simulator
from agents.decision_agent import agent as decision_agent
from agents.orchestrator import orchestrator


# ── request schemas ───────────────────────────────────────────────────────────
class SimulateRequest(BaseModel):
    """Request body schema for the /simulate endpoint."""
    crisis_type: str
    allocated_resources: Dict[str, Any]
    location: Optional[str] = "Unknown"


# ── lifespan: auto-start orchestrator on startup ──────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start the background orchestrator loop when the server boots."""
    asyncio.create_task(orchestrator.start())
    yield
    await orchestrator.stop()


# Initialize FastAPI Application
app = FastAPI(
    title="CIRO Multi-Hazard Crisis Orchestrator API",
    description="Backend coordinator for Fire, Flood & Heatwave Crisis Response",
    version="2.0.0",
    lifespan=lifespan,
)

# Configure Cross-Origin Resource Sharing (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for hackathon demo
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── routers ───────────────────────────────────────────────────────────────────
app.include_router(detect_router)
app.include_router(allocate_router)
app.include_router(signals_router)
app.include_router(ws_router)


# ── health ────────────────────────────────────────────────────────────────────
@app.get("/health")
async def health_check() -> Dict[str, str]:
    """
    Health check endpoint to verify the backend API is up and running.

    Returns:
        Dict[str, str]: A dictionary with key 'status' indicating service health.
    """
    return {"status": "ok"}


# ── debug ─────────────────────────────────────────────────────────────────────
@app.get("/debug")
def debug() -> Dict[str, Any]:
    """
    Debug endpoint to inspect current orchestrator state.

    Returns:
        Dict[str, Any]: Whether the orchestrator production loop is running.
    """
    return {"agents_running": orchestrator.running}


# ── traces ────────────────────────────────────────────────────────────────────
@app.get("/traces")
async def get_traces() -> List[Any]:
    """
    Reads all trace JSON files from the logs/demo_runs directory at the
    workspace root, sorted by their timestamp in the filename (descending),
    and returns a combined JSON array of all traces.

    Returns:
        List[Any]: Combined list of all parsed traces.
    """
    current_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_root = os.path.abspath(os.path.join(current_dir, ".."))
    log_dir = os.path.join(workspace_root, "logs", "demo_runs")

    search_pattern = os.path.join(log_dir, "*.json")
    file_paths = glob.glob(search_pattern)

    # Descending alphabetical order = newest-first for timestamped filenames
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


# ── detect ────────────────────────────────────────────────────────────────────
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
        # Image-only path — no fused signal; fusion happens via POST /signals
        decision = decision_agent.decide(
            detection_result=result,
            fused_signal=None,
        )
    finally:
        if os.path.exists(temp_filename):
            try:
                os.remove(temp_filename)
            except Exception:
                pass

    return {
        "detected":       result['detected'],
        "confidence":     result['confidence'],
        "crisis_type":    decision.get('crisis_type', 'fire'),
        "severity":       decision.get('severity', result.get('severity', 'none')),
        "action":         decision['action'],
        "recommendation": decision.get('recommendation', decision.get('reasoning', '')),
        "signal_sources": decision.get('signal_sources', ['image']),
        "decision":       decision,
    }


# ── simulate ─────────────────────────────────────────────────────────────────
@app.post("/simulate")
async def simulate(request: SimulateRequest) -> Dict[str, Any]:
    """
    Runs the ActionSimulator to compute before/after crisis state.

    Args:
        request (SimulateRequest): Crisis type, allocated resources, and location.

    Returns:
        Dict[str, Any]: Before/after state, impact metrics, and simulation metadata.
    """
    return simulator.simulate(
        crisis_type=request.crisis_type,
        allocated_resources=request.allocated_resources,
        location=request.location or "Unknown",
    )


if __name__ == "__main__":
    import uvicorn
    # Render sets the PORT environment variable automatically
    port = int(os.environ.get("PORT", 10000))
    # Run the uvicorn server on the configured port
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)

from contextlib import asynccontextmanager
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict, List, Any
import asyncio, json, os, glob

from routes.detect import router as detect_router
from websocket_endpoint import router as ws_router
from services.yolo_detector import detector
from agents.decision_agent import agent
from agents.orchestrator import orchestrator


# ── lifespan: auto-start orchestrator on startup ──────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start the background orchestrator loop when the server boots."""
    asyncio.create_task(orchestrator.start())
    yield
    await orchestrator.stop()


# Initialize FastAPI Application
app = FastAPI(
    title="CIRO Fire Orchestrator API",
    description="Backend coordinator for the Fire Crisis Response System",
    version="1.0.0",
    lifespan=lifespan,
)

# Configure Cross-Origin Resource Sharing (CORS)
# Support local development and Render deployment URLs.
allowed_origins = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:8000",
    "http://localhost:10000",
    "http://127.0.0.1",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8000",
    "http://127.0.0.1:10000",
]

# Read frontend/Render URLs from environment variables
env_origins = os.environ.get("ALLOWED_ORIGINS")
if env_origins:
    allowed_origins.extend([origin.strip() for origin in env_origins.split(",") if origin.strip()])

frontend_url = os.environ.get("FRONTEND_URL")
if frontend_url:
    allowed_origins.append(frontend_url.strip())

# Support Render external URL if defined
render_url = os.environ.get("RENDER_EXTERNAL_URL")
if render_url:
    allowed_origins.append(render_url.strip())

# Deduplicate origins
allowed_origins = list(set(allowed_origins))

# Fallback to wildcard if allowed_origins is empty or in local dev
if not allowed_origins or os.environ.get("ENV") == "development":
    allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True if "*" not in allowed_origins else False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── routers ───────────────────────────────────────────────────────────────────
app.include_router(detect_router)
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
        "decision": decision,
    }


if __name__ == "__main__":
    import uvicorn
    # Render sets the PORT environment variable automatically
    port = int(os.environ.get("PORT", 10000))
    # Run the uvicorn server on the configured port
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)

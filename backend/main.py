import os
import json
import glob
import uuid
import random
import logging
import asyncio
from datetime import datetime
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional
import time
import httpx
import aiohttp
from fastapi import FastAPI, UploadFile, File, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Routers (optional – comment out if files missing) ---
try:
    from routes.detect import router as detect_router
except ImportError:
    detect_router = None
try:
    from routes.allocate import router as allocate_router
except ImportError:
    allocate_router = None
try:
    from routes.signals import router as signals_router
except ImportError:
    signals_router = None
from websocket_endpoint import router as ws_router, manager as ws_manager

# --- YOLO detector (from services folder) ---
try:
    from services.yolo_detector import detector
    logger.info("✅ YOLO detector loaded from services.yolo_detector")
except ImportError as e:
    logger.error(f"Failed to load yolo_detector: {e}")
    # Fallback mock
    class MockDetector:
        def detect_fire(self, filepath): return {"detected": True, "confidence": 0.92, "severity": "high", "classes": ["fire"], "boxes": []}
    detector = MockDetector()

# --- Agents (fallback mocks if missing) ---
try:
    from agents.decision_agent import agent as decision_agent
except ImportError:
    class MockDecisionAgent:
        def decide(self, detection_result, fused_signal): return {"crisis_type": "fire", "action": "evacuate"}
    decision_agent = MockDecisionAgent()

try:
    from agents.orchestrator import orchestrator
except ImportError:
    class MockOrchestrator:
        async def start(self): pass
        async def stop(self): pass
        running = True
    orchestrator = MockOrchestrator()

# --- Antigravity & helpers ---
import antigravity_client
import resource_allocator
import simulation_engine
import notification_generator
from services.trace_logger import TraceLogger

# --- Global state ---
antigravity_traces: List[Dict[str, Any]] = []
session_traces: List[Dict[str, Any]] = []
active_crises: List[Dict[str, Any]] = []
available_units: Dict[str, int] = {"ambulances": 3, "police": 2, "fire_trucks": 2}
TOTAL_UNITS: Dict[str, int] = {"ambulances": 3, "police": 2, "fire_trucks": 2}

def allocate_resources(new_crisis: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    global active_crises, available_units
    if new_crisis is not None:
        if "allocated_resources" not in new_crisis:
            new_crisis["allocated_resources"] = {}
        active_crises.append(new_crisis)

    severity_map = {"high": 3, "medium": 2, "low": 1}
    type_map = {"fire": 3, "smoke": 2, "flood": 1, "accident": 1}

    active_crises.sort(
        key=lambda c: (
            severity_map.get(str(c.get("severity", "low")).lower(), 0),
            type_map.get(str(c.get("type", "accident")).lower(), 0)
        ),
        reverse=True
    )

    remaining = TOTAL_UNITS.copy()
    plan = {}

    for crisis in active_crises:
        cid = crisis.get("id")
        if not cid:
            continue
        ctype = str(crisis.get("type", "accident")).lower()
        sev = str(crisis.get("severity", "low")).lower()
        mult = severity_map.get(sev, 1)

        if ctype == "fire":
            needs = {"fire_trucks": 1 * mult, "ambulances": 1 * mult, "police": 1 * mult}
        elif ctype == "smoke":
            needs = {"fire_trucks": 1, "police": 1}
        elif ctype == "flood":
            needs = {"ambulances": 1 * mult, "police": 1 * mult}
        else:
            needs = {"ambulances": 1 * mult, "police": 1 * mult}

        allocated = {}
        for res, needed in needs.items():
            if res in remaining and remaining[res] > 0:
                given = min(needed, remaining[res])
                allocated[res] = given
                remaining[res] -= given
        crisis["allocated_resources"] = allocated
        plan[cid] = allocated

    available_units = remaining
    return {"allocation_plan": plan, "remaining_resources": remaining}

# --- Pydantic models ---
class VerifyRequest(BaseModel):
    crisis_id: str
    verified: bool
    user_notes: Optional[str] = None

class ResolveRequest(BaseModel):
    crisis_id: str

class LocalDetectionEventRequest(BaseModel):
    detections: List[Dict[str, Any]]
    location: str
    test_mode: Optional[bool] = False

# --- Lifespan ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 CIRO backend starting up on http://0.0.0.0:8000")
    asyncio.create_task(orchestrator.start())
    yield
    logger.info("🛑 CIRO backend shutting down.")
    await orchestrator.stop()

app = FastAPI(title="CIRO Multi-Hazard Crisis Orchestrator API", version="4.0.0", lifespan=lifespan)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Include routers (only if they exist)
if allocate_router:
    app.include_router(allocate_router)
if signals_router:
    app.include_router(signals_router)
app.include_router(ws_router)

# ==================== HEALTH & TRACES ====================
@app.get("/health")
async def health_check() -> Dict[str, str]:
    return {"status": "ok"}

@app.get("/debug")
def debug() -> Dict[str, Any]:
    return {
        "agents_running": orchestrator.running,
        "active_crises_count": len(active_crises),
        "available_units": available_units
    }

@app.get("/traces")
async def get_traces() -> List[Any]:
    # Also read from trace_logger files
    all_traces = list(session_traces)
    current_dir = os.path.dirname(os.path.abspath(__file__))
    log_dir = os.path.join(current_dir, "logs", "demo_runs")
    if os.path.exists(log_dir):
        for file_path in glob.glob(os.path.join(log_dir, "*.json")):
            try:
                with open(file_path, "r") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        all_traces.extend(data)
                    else:
                        all_traces.append(data)
            except:
                pass
    return all_traces

# ==================== WEATHER & TRAFFIC (Real APIs) ====================
_api_cache = {}
CACHE_TTL = 300

@app.get("/weather")
async def get_weather(lat: float = 33.6844, lon: float = 73.0479, fallback_to_mock: bool = False) -> Dict[str, Any]:
    cache_key = (lat, lon, 'weather')
    now = time.time()
    if cache_key in _api_cache and now - _api_cache[cache_key][0] < CACHE_TTL:
        return _api_cache[cache_key][1]

    if not fallback_to_mock:
        try:
            async with aiohttp.ClientSession() as session:
                url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
                async with session.get(url, timeout=5.0) as resp:
                    resp.raise_for_status()
                    data = await resp.json()
                    current = data.get("current_weather", {})
                    code = current.get("weathercode", 0)
                    if code in [1,2,3]:
                        condition, icon, desc = "clouds", "☁️", "Cloudy"
                    elif code in [45,48]:
                        condition, icon, desc = "fog", "🌫️", "Foggy"
                    elif code in [51,53,55,56,57,61,63,65,66,67,80,81,82]:
                        condition, icon, desc = "rain", "🌧️", "Rainy"
                    elif code in [71,73,75,77,85,86]:
                        condition, icon, desc = "snow", "❄️", "Snowy"
                    elif code in [95,96,99]:
                        condition, icon, desc = "thunderstorm", "⛈️", "Thunderstorm"
                    else:
                        condition, icon, desc = "clear", "☀️", "Clear"
                    result = {
                        "condition": condition,
                        "weather_description": desc,
                        "weather_icon": icon,
                        "intensity": current.get("windspeed", 0),
                        "temp_c": current.get("temperature", 22),
                        "humidity": 50
                    }
                    _api_cache[cache_key] = (now, result)
                    return result
        except Exception as e:
            logger.error(f"Weather API failed: {e}")
    # Mock fallback
    return {"condition": "rain", "weather_description": "Mock Rain", "weather_icon": "🌧️", "intensity": 8, "temp_c": 22, "humidity": 85}

@app.get("/traffic")
async def get_traffic(lat: float = 33.6844, lon: float = 73.0479, fallback_to_mock: bool = False) -> Dict[str, Any]:
    cache_key = (lat, lon, 'traffic')
    now = time.time()
    if cache_key in _api_cache and now - _api_cache[cache_key][0] < CACHE_TTL:
        return _api_cache[cache_key][1]

    tomtom_api_key = os.environ.get("TOMTOM_API_KEY")
    if not fallback_to_mock and tomtom_api_key:
        try:
            async with httpx.AsyncClient() as client:
                url = f"https://api.tomtom.com/traffic/services/4/flowSegmentData/absolute/10/json?point={lat},{lon}&key={tomtom_api_key}"
                resp = await client.get(url, timeout=5.0)
                resp.raise_for_status()
                data = resp.json()
                flow = data.get("flowSegmentData", {})
                current_speed = flow.get("currentSpeed", 12)
                free_flow = flow.get("freeFlowSpeed", 50)
                if current_speed < free_flow * 0.5:
                    congestion = "high"
                elif current_speed < free_flow * 0.8:
                    congestion = "medium"
                else:
                    congestion = "low"
                result = {"congestion": congestion, "speed_kmh": current_speed, "incidents": []}
                _api_cache[cache_key] = (now, result)
                return result
        except Exception as e:
            logger.error(f"Traffic API failed: {e}")
    return {"congestion": "high", "speed_kmh": 12, "incidents": ["accident at G-10"]}

# ==================== DETECTION ENDPOINTS ====================
@app.post("/detect")
async def detect(
    image: UploadFile = File(...),
    social_text: Optional[str] = Form(None),
    lat: float = Form(33.6844),
    lon: float = Form(73.0479),
    test_mode: bool = Form(False)
) -> Dict[str, Any]:
    temp_filename = f"temp_{image.filename or 'image.jpg'}"
    contents = await image.read()
    with open(temp_filename, "wb") as f:
        f.write(contents)

    try:
        # Run YOLO detection
        result = detector.detect_fire(temp_filename)
        classes_detected = result.get("classes", [])
        boxes = result.get("boxes", [])
        max_confidence = result.get("confidence", 0.0)

        if "fire" in classes_detected:
            crisis_type = "fire"
        elif "smoke" in classes_detected:
            crisis_type = "smoke"
        else:
            crisis_type = "fire"

        result["detected"] = len(classes_detected) > 0
        result["confidence"] = max_confidence
        result["severity"] = "high" if max_confidence > 0.8 else "medium" if max_confidence > 0.5 else "low"

        if test_mode:
            result["confidence"] = 0.25
            logger.info("Test Mode: low confidence set")
        elif random.random() < 0.20:
            result["confidence"] *= 0.5

        requires_human_review = result["confidence"] < 0.40

        try:
            decision = decision_agent.decide(detection_result=result, fused_signal=None)
        except:
            decision = {"crisis_type": crisis_type, "action": "evacuate"}

        action_upper = decision.get("action", "monitor").upper()
        if action_upper not in ["EVACUATE", "WARNING", "MONITOR"]:
            action_upper = "MONITOR"

        weather_data = await get_weather(lat, lon)
        traffic_data = await get_traffic(lat, lon)
        location_str = f"{lat},{lon}"

        crisis_context = {
            "crisis_type": crisis_type,
            "severity": max_confidence,
            "location": location_str,
            "weather": weather_data,
            "traffic": traffic_data,
            "social_text": social_text,
            "test_mode": test_mode,
            "detections": boxes
        }

        try:
            ag_plan = antigravity_client.plan(crisis_context)  # returns dict with 'traces' key
        except Exception as e:
            ag_plan = {"error": str(e), "workplan": [], "reasoning": "Fallback", "traces": []}

        crisis_id = str(uuid.uuid4())
        new_crisis = {
            "id": crisis_id,
            "type": crisis_type,
            "severity": max_confidence,
            "location": location_str,
            "timestamp": datetime.now().isoformat(),
            "status": "verification_required" if requires_human_review else "active"
        }

        crisis_allocation = {}
        sim_results = {}
        notifications = []

        if requires_human_review:
            new_crisis["allocated_resources"] = {}
            active_crises.append(new_crisis)
            action_upper = "VERIFICATION_REQUIRED"
        else:
            allocation_result = allocate_resources(new_crisis)
            crisis_allocation = allocation_result["allocation_plan"].get(crisis_id, {})
            new_crisis["allocated_resources"] = crisis_allocation
            sim_results = simulation_engine.simulate_action(crisis_type, location_str, crisis_allocation)
            notifications = notification_generator.generate_notifications(crisis_type, max_confidence, location_str, crisis_allocation)

        antigravity_traces.append(ag_plan)

        # Append traces from antigravity_client
        for trace in ag_plan.get("traces", []):
            session_traces.append(trace)

        # Also add orchestrator trace
        orchestrator_trace = {
            "agent_name": "orchestrator",
            "step_type": "ACT",
            "reasoning": ag_plan.get("reasoning", "Analysis completed."),
            "confidence_before": 0.0,
            "confidence_after": result["confidence"],
            "timestamp": datetime.now().isoformat()
        }
        session_traces.append(orchestrator_trace)

        # Write to trace logger
        trace_logger = TraceLogger()
        for t in ag_plan.get("traces", []):
            try:
                trace_logger.write_trace(**{k: v for k,v in t.items() if k in ["agent_name","step_type","reasoning","confidence_before","confidence_after","inputs","output","tool_calls","duration_ms","timestamp"]})
            except:
                pass

        response_data = {
            "crisis_id": crisis_id,
            "detected": result["detected"],
            "confidence": result["confidence"],
            "escalation_required": requires_human_review,
            "crisis_type": crisis_type,
            "severity": result["severity"],
            "action": action_upper,
            "antigravity_plan": ag_plan.get("workplan", []),
            "reasoning": ag_plan.get("reasoning", ""),
            "allocation_plan": crisis_allocation,
            "simulation": sim_results,
            "notifications": notifications,
            "test_mode_active": test_mode,
            "detections": boxes
        }

        await ws_manager.broadcast_alert(response_data)
        return response_data

    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

@app.post("/detect_video")
async def detect_video(
    video: UploadFile = File(...),
    social_text: Optional[str] = Form(None),
    lat: float = Form(33.6844),
    lon: float = Form(73.0479),
    test_mode: bool = Form(False)
) -> Dict[str, Any]:
    import cv2
    temp_filename = f"temp_{video.filename or 'video.mp4'}"
    contents = await video.read()
    with open(temp_filename, "wb") as f:
        f.write(contents)

    try:
        cap = cv2.VideoCapture(temp_filename)
        frame_interval = 30
        frame_count = 0
        overall_detected = False
        max_confidence = 0.0
        classes_detected = []
        all_boxes = []

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            if frame_count % frame_interval == 0:
                tf = f"temp_frame_{frame_count}.jpg"
                cv2.imwrite(tf, frame)
                result = detector.detect_fire(tf)
                if result.get("detected"):
                    overall_detected = True
                    classes_detected.extend(result.get("classes", []))
                    all_boxes.extend(result.get("boxes", []))
                    if result.get("confidence", 0) > max_confidence:
                        max_confidence = result.get("confidence", 0)
                if os.path.exists(tf):
                    os.remove(tf)
            frame_count += 1
        cap.release()

        if "fire" in classes_detected:
            crisis_type = "fire"
        elif "smoke" in classes_detected:
            crisis_type = "smoke"
        else:
            crisis_type = "fire"

        location_str = f"{lat},{lon}"
        weather_data = await get_weather(lat, lon)
        traffic_data = await get_traffic(lat, lon)
        crisis_context = {
            "crisis_type": crisis_type,
            "severity": max_confidence,
            "location": location_str,
            "weather": weather_data,
            "traffic": traffic_data,
            "social_text": social_text,
            "test_mode": test_mode,
            "detections": all_boxes
        }
        ag_plan = antigravity_client.plan(crisis_context)

        return {
            "detected": overall_detected,
            "confidence": max_confidence,
            "crisis_type": crisis_type,
            "severity": "high" if max_confidence > 0.8 else "medium" if max_confidence > 0.5 else "low",
            "action": ag_plan.get("final_decision", "monitor").upper(),
            "antigravity_plan": ag_plan.get("workplan", []),
            "reasoning": ag_plan.get("reasoning", ""),
            "allocation_plan": ag_plan.get("allocation_plan", {}),
            "simulation": ag_plan.get("simulation", {}),
            "notifications": ag_plan.get("notifications", []),
            "detections": all_boxes
        }
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)

# ==================== LOCAL DETECTION EVENT ====================
@app.post("/local_detection_event")
async def local_detection_event(request: Request):
    data = await request.json()
    detections = data.get("detections", [])
    location = data.get("location", "unknown")
    max_conf = 0.0
    crisis_type = None
    for d in detections:
        conf = d.get("confidence", 0)
        if conf > max_conf:
            max_conf = conf
            crisis_type = d.get("label")
    if max_conf > 0.6 and crisis_type:
        context = {
            "crisis_type": crisis_type,
            "severity": max_conf,
            "location": location,
            "weather": {"condition": "unknown"},
            "traffic": {"congestion": "unknown"},
            "social_text": f"Local detection: {crisis_type}"
        }
        plan_dict = antigravity_client.plan(context)
        antigravity_traces.append(plan_dict)
        for trace in plan_dict.get("traces", []):
            antigravity_traces.append(trace)
        allocation = resource_allocator.allocate_resources({"type": crisis_type, "severity": max_conf})
        simulation = simulation_engine.simulate_action(crisis_type, location, allocation)
        notifications = notification_generator.generate_notifications(crisis_type, max_conf, location, allocation)
        return {"status": "logged", "plan": plan_dict, "simulation": simulation, "notifications": notifications, "allocation": allocation}
    else:
        return {"status": "ignored", "reason": "low confidence"}

# ==================== CRISIS STATE MANAGEMENT ====================
@app.get("/crises")
async def get_crises() -> Dict[str, Any]:
    return {"active_crises": active_crises, "available_units": available_units}

@app.post("/retract_crisis/{crisis_id}")
async def retract_crisis(crisis_id: str, user_notes: Optional[str] = None) -> Dict[str, Any]:
    global active_crises
    target = next((c for c in active_crises if c.get("id") == crisis_id), None)
    if not target:
        return {"status": "error", "message": "Crisis not found"}
    active_crises.remove(target)
    allocate_resources()
    reasoning = "False alarm – retracted by commander."
    if user_notes:
        reasoning += f" Notes: {user_notes}"
    session_traces.append({
        "agent_name": "orchestrator",
        "step_type": "EVALUATE",
        "reasoning": reasoning,
        "confidence_before": 0.6,
        "confidence_after": 0.0,
        "timestamp": datetime.now().isoformat()
    })
    antigravity_traces.append({
        "antigravity_trace_id": str(uuid.uuid4()),
        "workplan": ["retract_crisis", "stand_down_units"],
        "reasoning": reasoning,
        "final_decision": "stand_down",
        "allocation_plan": {},
        "simulation": {"eta_reduction_minutes": 0, "traffic_reroute": False, "side_effects": "None"},
        "notifications": [{"target": "command_center", "message": f"Crisis {crisis_id} retracted."}]
    })
    return {"status": "retracted", "message": "Crisis marked as false alarm"}

@app.post("/verify_crisis")
async def verify_crisis(req: VerifyRequest) -> Dict[str, Any]:
    if not req.verified:
        return await retract_crisis(req.crisis_id, req.user_notes)
    global active_crises
    crisis = next((c for c in active_crises if c["id"] == req.crisis_id), None)
    if not crisis:
        return {"status": "error", "message": "Crisis ID not found."}
    crisis["status"] = "active"
    allocation_result = allocate_resources()
    session_traces.append({
        "agent_name": "orchestrator",
        "step_type": "ACT",
        "reasoning": f"Crisis {req.crisis_id} manually verified by commander. Resources dispatched.",
        "confidence_before": 0.4,
        "confidence_after": 0.95,
        "timestamp": datetime.now().isoformat()
    })
    return {
        "status": "success",
        "message": f"Crisis {req.crisis_id} verified and escalated.",
        "allocation": allocation_result["allocation_plan"].get(req.crisis_id, {})
    }

@app.post("/resolve_crisis/{crisis_id}")
async def resolve_crisis(crisis_id: str) -> Dict[str, Any]:
    global active_crises
    target = next((c for c in active_crises if c.get("id") == crisis_id), None)
    if not target:
        return {"status": "error", "message": "Crisis not found"}
    freed = target.get("allocated_resources", {})
    active_crises.remove(target)
    allocate_resources()
    return {
        "status": "success",
        "message": f"Crisis {crisis_id} resolved.",
        "freed_resources": freed,
        "available_units": available_units
    }

# ==================== ANTIGRAVITY EXPORTS ====================
@app.get("/antigravity_traces")
async def get_antigravity_traces() -> List[Dict[str, Any]]:
    return antigravity_traces

@app.get("/antigravity_traces/export")
async def export_antigravity_traces():
    json_data = json.dumps(antigravity_traces, indent=4)
    return Response(content=json_data, media_type="application/json", headers={"Content-Disposition": "attachment; filename=antigravity_export.json"})

# ==================== ANALYTICS ====================
@app.get("/analytics")
async def get_analytics() -> Dict[str, Any]:
    from datetime import datetime, timedelta
    traces = await get_traces()
    today = datetime.now()
    dates = [(today - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(6, -1, -1)]
    crises_per_day = {d: 0 for d in dates}
    conf_sum = {"fire": 0.0, "smoke": 0.0}
    conf_count = {"fire": 0, "smoke": 0}
    for t in traces:
        ts = t.get("timestamp", "")
        if not ts:
            continue
        try:
            dt = datetime.fromisoformat(ts) if "T" in ts else datetime.strptime(ts, "%Y%m%d_%H%M%S")
        except:
            dt = today
        d_str = dt.strftime("%Y-%m-%d")
        if t.get("step_type") == "ACT" and t.get("agent_name") == "orchestrator":
            if d_str in crises_per_day:
                crises_per_day[d_str] += 1
        if "confidence_after" in t:
            c_type = "fire"
            reasoning = str(t.get("reasoning", "")).lower()
            if "smoke" in reasoning:
                c_type = "smoke"
            conf_sum[c_type] += t["confidence_after"]
            conf_count[c_type] += 1
    avg_conf = {ct: (conf_sum[ct]/conf_count[ct]) if conf_count[ct] else 0 for ct in ["fire","smoke"]}
    return {
        "crises_per_day": [{"date": d, "count": crises_per_day[d]} for d in dates],
        "avg_confidence": avg_conf,
        "resources_per_day": []  # can be extended
    }

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
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

from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Existing Core Services & Agents ---
# (Ensure these routers exist in your workspace, or comment them out if not used)
from routes.detect import router as detect_router
from routes.allocate import router as allocate_router
from routes.signals import router as signals_router
from websocket_endpoint import router as ws_router

# Mock fallbacks in case the actual modules are not yet implemented locally
try:
    from services.yolo_detector import detector
except ImportError:
    class MockDetector:
        def detect_fire(self, filepath): return {"detected": True, "confidence": 0.92, "severity": "high"}
    detector = MockDetector()

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

# --- New Modules Integration ---
import antigravity_client
import resource_allocator
import simulation_engine
import notification_generator
from services.trace_logger import TraceLogger

# --- Global State Management ---
antigravity_traces: List[Dict[str, Any]] = []
session_traces: List[Dict[str, Any]] = []

active_crises: List[Dict[str, Any]] = []
available_units: Dict[str, int] = {"ambulances": 3, "police": 2, "fire_trucks": 2}
TOTAL_UNITS: Dict[str, int] = {"ambulances": 3, "police": 2, "fire_trucks": 2}

def allocate_resources(new_crisis: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Allocates available resources to active crises based on a priority queue.
    
    Args:
        new_crisis (Optional[Dict[str, Any]]): The new crisis to add to the pool.
        
    Returns:
        Dict[str, Any]: The full allocation plan and remaining available resources.
    """
    global active_crises, available_units
    
    if new_crisis is not None:
        if "allocated_resources" not in new_crisis:
            new_crisis["allocated_resources"] = {}
        active_crises.append(new_crisis)
        
    severity_map = {"high": 3, "medium": 2, "low": 1}
    type_map = {"fire": 3, "flood": 2, "accident": 1}
    
    # Sort crises by severity (high to low) and then by type priority
    active_crises.sort(
        key=lambda c: (
            severity_map.get(str(c.get("severity", "low")).lower(), 0),
            type_map.get(str(c.get("type", "accident")).lower(), 0)
        ),
        reverse=True
    )
    
    remaining = TOTAL_UNITS.copy()
    plan = {}
    
    # Iterate sorted list and assign resources until exhausted
    for crisis in active_crises:
        cid = crisis.get("id")
        if not cid: continue
            
        ctype = str(crisis.get("type", "accident")).lower()
        sev = str(crisis.get("severity", "low")).lower()
        mult = severity_map.get(sev, 1)
        
        if ctype == "fire":
            needs = {"fire_trucks": 1 * mult, "ambulances": 1 * mult, "police": 1 * mult}
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
        
    available_units.clear()
    available_units.update(remaining)
    
    return {"allocation_plan": plan, "remaining_resources": remaining}

# --- Request Models ---
class VerifyRequest(BaseModel):
    crisis_id: str
    verified: bool
    user_notes: Optional[str] = None

class ResolveRequest(BaseModel):
    crisis_id: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    asyncio.create_task(orchestrator.start())
    yield
    await orchestrator.stop()


app = FastAPI(
    title="CIRO Multi-Hazard Crisis Orchestrator API",
    description="Backend coordinator with YOLO, Antigravity, and Full Operations",
    version="4.0.0",
    lifespan=lifespan,
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Include standard routers (ignoring detect_router to use our advanced one below)
app.include_router(allocate_router)
app.include_router(signals_router)
app.include_router(ws_router)


# ==========================================
# SYSTEM & TRACE ENDPOINTS
# ==========================================

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
    current_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_root = os.path.abspath(os.path.join(current_dir, ".."))
    log_dir = os.path.join(workspace_root, "logs", "demo_runs")
    search_pattern = os.path.join(log_dir, "*.json")
    file_paths = glob.glob(search_pattern)
    file_paths.sort(reverse=True)
    all_traces = []

    for file_path in file_paths:
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    all_traces.extend(data)
                else:
                    all_traces.append(data)
        except Exception:
            pass

    return session_traces + all_traces


# ==========================================
# MULTI-SIGNAL FUSION MOCKS
# ==========================================

@app.get("/weather")
async def get_weather(lat: Optional[float] = 33.6844, lon: Optional[float] = 73.0479) -> Dict[str, Any]:
    return {"condition": "heavy rain", "intensity": 8, "temp_c": 22, "humidity": 85}

@app.get("/traffic")
async def get_traffic(lat: Optional[float] = 33.6844, lon: Optional[float] = 73.0479) -> Dict[str, Any]:
    return {"congestion": "high", "speed_kmh": 12, "incidents": ["accident at G-10"]}


# ==========================================
# CORE PIPELINE: DETECT & ORCHESTRATE
# ==========================================

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
        # 1. YOLO Detection
        result = detector.detect_fire(temp_filename)
        result.setdefault("detected", True)
        result.setdefault("confidence", 0.92)
        result.setdefault("severity", "high")

        # --- Test Mode Randomness ---
        if test_mode:
            result["confidence"] = 0.25
            logger.info("Test Mode: Artificially set confidence to 0.25 to force Commander verification.")
            if social_text:
                social_text = f"[CONFLICTING SIGNAL]: YOLO indicates fire, but weather indicates normal. {social_text}"
        elif random.random() < 0.20:
            result["confidence"] *= 0.5
            logger.info("Test Mode Randomness: Artificially reduced confidence.")
            if social_text:
                social_text = f"[CONFLICTING SIGNAL]: YOLO indicates fire, but weather indicates normal. {social_text}"

        # 2. Low-Confidence Escalation Check
        requires_human_review = result["confidence"] < 0.40

        try:
            decision = decision_agent.decide(detection_result=result, fused_signal=None)
        except Exception:
            decision = {"crisis_type": "fire", "action": "evacuate"}

        action_upper = decision.get("action", "monitor").upper()
        if action_upper not in ["EVACUATE", "WARNING", "MONITOR"]:
            action_upper = "MONITOR"

        weather_data = await get_weather(lat, lon)
        traffic_data = await get_traffic(lat, lon)
        location_str = f"{lat},{lon}"

        crisis_context = {
            "crisis_type": decision.get("crisis_type", "fire"),
            "severity": result.get("confidence", 0.92),
            "location": location_str,
            "weather": weather_data,
            "traffic": traffic_data,
            "social_text": social_text,
            "test_mode": test_mode
        }

        try:
            ag_plan = antigravity_client.plan(crisis_context)
        except Exception as e:
            ag_plan = {"error": str(e), "workplan": [], "reasoning": "Fallback applied.", "traces": []}

        # 3. Crisis Management & Conditional Allocation
        crisis_id = str(uuid.uuid4())
        new_crisis = {
            "id": crisis_id,
            "type": crisis_context["crisis_type"],
            "severity": crisis_context["severity"],
            "location": location_str,
            "timestamp": datetime.now().isoformat(),
            "status": "verification_required" if requires_human_review else "active"
        }

        crisis_allocation = {}
        waiting_list = []
        sim_results = {}
        notifications = []

        if requires_human_review:
            new_crisis["allocated_resources"] = {}
            active_crises.append(new_crisis)
            ag_plan["reasoning"] = f"⚠️ Low confidence ({result['confidence']:.2f}). Escalated for Commander verification. Resources held."
            action_upper = "VERIFICATION_REQUIRED"
        else:
            allocation_result = allocate_resources(new_crisis)
            full_allocation_plan = allocation_result["allocation_plan"]
            crisis_allocation = full_allocation_plan.get(crisis_id, {})

            ag_plan["multi_crisis_plan"] = {
                "total_active_crises": len(active_crises),
                "full_network_allocation": full_allocation_plan,
            }

            new_crisis["allocated_resources"] = crisis_allocation
            sim_results = simulation_engine.simulate_action(full_allocation_plan, new_crisis)
            notifications = notification_generator.generate_notifications(
                crisis_type=new_crisis.get("type", "fire"),
                severity=new_crisis.get("severity", 0.92),
                location=new_crisis.get("location", "Unknown"),
                allocation_plan=crisis_allocation
            )

        antigravity_traces.append(ag_plan)
        
        # Append the orchestrator ACT trace
        orchestrator_trace = {
            "agent_name": "orchestrator",
            "step_type": "ACT",
            "reasoning": ag_plan.get("reasoning", "Analysis completed."),
            "confidence_before": 0.0,
            "confidence_after": result.get("confidence", 0.92),
            "timestamp": datetime.now().isoformat()
        }
        session_traces.append(orchestrator_trace)

        # Write traces for all individual agents from Antigravity mock plan
        trace_logger = TraceLogger()
        for t in ag_plan.get("traces", []):
            session_traces.append(t)
            try:
                trace_logger.write_trace(
                    agent_name=t.get("agent_name"),
                    step_type=t.get("step_type"),
                    reasoning=t.get("reasoning"),
                    confidence_before=t.get("confidence_before"),
                    confidence_after=t.get("confidence_after"),
                    inputs=t.get("inputs"),
                    output=t.get("output"),
                    tool_calls=t.get("tool_calls"),
                    duration_ms=t.get("duration_ms", 0),
                    timestamp=t.get("timestamp")
                )
            except Exception as e:
                logger.error(f"Error logging agent trace: {e}")

        # Also write orchestrator trace
        try:
            trace_logger.write_trace(
                agent_name=orchestrator_trace["agent_name"],
                step_type=orchestrator_trace["step_type"],
                reasoning=orchestrator_trace["reasoning"],
                confidence_before=orchestrator_trace["confidence_before"],
                confidence_after=orchestrator_trace["confidence_after"],
                timestamp=orchestrator_trace["timestamp"]
            )
        except Exception as e:
            logger.error(f"Error logging orchestrator trace: {e}")

        return {
            "crisis_id": crisis_id,
            "detected": result.get("detected", True),
            "confidence": result.get("confidence", 0.92),
            "escalation_required": requires_human_review,
            "crisis_type": decision.get("crisis_type", "fire"),
            "severity": decision.get("severity", result.get("severity", "high")),
            "action": action_upper,
            "antigravity_plan": ag_plan.get("workplan", []),
            "reasoning": ag_plan.get("reasoning", ""),
            "allocation_plan": crisis_allocation,
            "is_waitlisted": crisis_id in waiting_list,
            "simulation": ag_plan.get("simulation", sim_results),
            "notifications": ag_plan.get("notifications", notifications),
            "test_mode_active": test_mode
        }

    finally:
        if os.path.exists(temp_filename):
            try:
                os.remove(temp_filename)
            except:
                pass


# ==========================================
# CRISIS STATE & FALSE ALARM HANDLING
# ==========================================

@app.get("/crises")
async def get_crises() -> Dict[str, Any]:
    """Returns the Crisis Dashboard: all active crises and current resource pool."""
    return {
        "active_crises": active_crises,
        "available_units": available_units
    }


@app.post("/retract_crisis/{crisis_id}")
async def retract_crisis(crisis_id: str, user_notes: Optional[str] = None) -> Dict[str, Any]:
    """Retracts a false alarm directly, frees resources, and logs traces."""
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
    """Manually verify a low-confidence crisis or flag a false positive."""
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
    """Marks a crisis as safely resolved and returns its resources to the global pool."""
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


# ==========================================
# ANTIGRAVITY EXPORTS
# ==========================================

@app.get("/antigravity_traces")
async def get_antigravity_traces() -> List[Dict[str, Any]]:
    return antigravity_traces

@app.get("/antigravity_traces/export")
async def export_antigravity_traces():
    """Exports all Antigravity plans as a downloadable JSON file."""
    json_data = json.dumps(antigravity_traces, indent=4)
    return Response(
        content=json_data,
        media_type="application/json",
        headers={"Content-Disposition": "attachment; filename=antigravity_export.json"}
    )


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
"""
signals.py
----------
POST /signals endpoint — multi-source crisis signal fusion.

Accepts a social-media text post and an optional location string,
then fuses weather + social signals (+ a placeholder image score of 0.0
when no image is uploaded) into a single crisis assessment that is
returned to the caller and fully traced.
"""

from typing import Any, Dict, Optional

from fastapi import APIRouter
from pydantic import BaseModel

from services.signal_fusion import signal_fusion
from services.trace_logger import TraceLogger

router = APIRouter(tags=["Signals"])

# Shared logger for the route layer
_logger = TraceLogger()


# ---------------------------------------------------------------------------
# Request / Response schemas
# ---------------------------------------------------------------------------
class SignalRequest(BaseModel):
    """Payload accepted by POST /signals."""

    text_input: str
    location: Optional[str] = "Karachi"


class SignalResponse(BaseModel):
    """Structured response from POST /signals."""

    fused_score: float
    dominant_crisis: str
    action: str
    sources: Dict[str, Any]
    weather: Dict[str, Any]
    social: Dict[str, Any]
    trace_logged: bool = True


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------
@router.post("/signals", response_model=SignalResponse)
async def analyze_signals(payload: SignalRequest) -> Dict[str, Any]:
    """
    Fuse weather and social signals into a crisis assessment.

    The image source defaults to 0.0 score when no image is supplied
    (use POST /detect for image-based detection).

    Args:
        payload (SignalRequest): text_input and optional location.

    Returns:
        Dict[str, Any]: Fused crisis score, dominant type, action, and per-source detail.
    """
    _logger.write_trace(
        agent_name="signals_route",
        step_type="OBSERVE",
        reasoning=f"Received /signals request — text='{payload.text_input[:60]}', location='{payload.location}'",
        inputs={"text_input": payload.text_input, "location": payload.location},
        output={},
        confidence_before=0.0,
        confidence_after=0.0,
        tool_calls=[],
        duration_ms=0,
    )

    # --- Collect individual source signals --------------------------------
    weather_result = signal_fusion.get_weather_signal(location=payload.location)
    social_result  = signal_fusion.get_social_signal(text_input=payload.text_input)

    # No image uploaded → pass None; fusion handles it gracefully
    fused = signal_fusion.fuse(
        image_result=None,
        weather_result=weather_result,
        social_result=social_result,
    )

    # --- Derive recommended action from fused score -----------------------
    score = fused["fused_score"]
    if score >= 0.7:
        action = "evacuate"
    elif score >= 0.4:
        action = "warning"
    else:
        action = "monitor"

    _logger.write_trace(
        agent_name="signals_route",
        step_type="DECIDE",
        reasoning=(
            f"fused_score={score:.3f} → action='{action}', "
            f"dominant_crisis='{fused['dominant_crisis']}'"
        ),
        inputs={"fused_score": score, "dominant_crisis": fused["dominant_crisis"]},
        output={"action": action},
        confidence_before=0.5,
        confidence_after=score,
        tool_calls=[],
        duration_ms=1,
    )

    return {
        "fused_score":      fused["fused_score"],
        "dominant_crisis":  fused["dominant_crisis"],
        "action":           action,
        "sources":          fused["sources"],
        "weather":          weather_result,
        "social":           social_result,
        "trace_logged":     True,
    }

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

    social_text: Optional[str] = ""         # citizen report text (optional)
    text_input:  Optional[str] = None       # legacy alias — overrides social_text if set
    location:    Optional[str] = "Karachi"


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
    Fuse weather, social, and image (default 0.0) signals into a crisis assessment.

    Accepts an optional social report text and optional location string.
    The image source defaults to 0.0 when no image is supplied
    (use POST /detect for image-based detection).

    Args:
        payload (SignalRequest): social_text, optional text_input (legacy), and location.

    Returns:
        Dict[str, Any]: Fused crisis score, dominant type, action, and per-source detail.
    """
    # Resolve text: text_input overrides social_text if explicitly provided
    resolved_text: str = payload.text_input or payload.social_text or ""

    _logger.write_trace(
        agent_name="signals_route",
        step_type="OBSERVE",
        reasoning=(
            f"Received /signals request — "
            f"social_text='{resolved_text[:60]}', location='{payload.location}'"
        ),
        inputs={"social_text": resolved_text, "location": payload.location},
        output={},
        confidence_before=0.0,
        confidence_after=0.0,
        tool_calls=[],
        duration_ms=0,
    )

    # --- Source 1: Weather signal (mock – no API key needed) ---------------
    weather_result = signal_fusion.get_weather_signal(location=payload.location)

    _logger.write_trace(
        agent_name="signals_route.weather",
        step_type="OBSERVE",
        reasoning=(
            f"Weather source polled — crisis_type='{weather_result['crisis_type']}', "
            f"crisis_score={weather_result['crisis_score']:.2f}"
        ),
        inputs={"location": payload.location},
        output=weather_result,
        confidence_before=0.0,
        confidence_after=weather_result["crisis_score"],
        tool_calls=[],
        duration_ms=5,
    )

    # --- Source 2: Social / citizen-report signal --------------------------
    social_result = signal_fusion.get_social_signal(text_input=resolved_text)

    _logger.write_trace(
        agent_name="signals_route.social",
        step_type="OBSERVE",
        reasoning=(
            f"Social source scanned — detected='{social_result['detected_crisis']}', "
            f"confidence={social_result['confidence']:.2f}"
        ),
        inputs={"social_text": resolved_text},
        output=social_result,
        confidence_before=0.0,
        confidence_after=social_result["confidence"],
        tool_calls=[],
        duration_ms=2,
    )

    # --- Source 3: Image — no image upload here; default 0.0 score ---------
    # (Use POST /detect for image-based fusion)
    fused = signal_fusion.fuse(
        image_result=None,        # // mock: no image → image score defaults to 0.0
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
        "fused_score":     fused["fused_score"],
        "dominant_crisis": fused["dominant_crisis"],
        "action":          action,
        "sources":         fused["sources"],
        "weather":         weather_result,
        "social":          social_result,
        "trace_logged":    True,
    }


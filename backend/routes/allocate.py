"""
allocate.py
-----------
FastAPI router exposing the POST /allocate endpoint for
emergency resource allocation via the ResourceAllocator service.
"""

from typing import Any, Dict
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services.resource_allocator import allocator
from services.trace_logger import TraceLogger

router = APIRouter(tags=["Resource Allocation"])

# Module-level logger for endpoint-level traces
_logger = TraceLogger()


# ── Request / Response schemas ─────────────────────────────────────────────────

class AllocateRequest(BaseModel):
    """Input schema for the resource allocation endpoint."""

    crisis_type: str = Field(
        ...,
        description="Type of crisis: 'fire' | 'flood' | 'heatwave'",
        example="fire",
    )
    severity: str = Field(
        ...,
        description="Severity level: 'high' | 'medium' | 'low' | 'none'",
        example="high",
    )
    location: str = Field(
        ...,
        description="Human-readable location of the incident",
        example="Sector 7, Karachi",
    )


class AllocateResponse(BaseModel):
    """Typed response schema returned by the allocation endpoint."""

    allocated_resources: list
    units_dispatched: Dict[str, int]
    estimated_arrival_min: float
    coverage_score: float
    resource_status: Dict[str, Any]
    location: str
    timestamp: float


# ── Endpoint ───────────────────────────────────────────────────────────────────

@router.post("/allocate", response_model=AllocateResponse)
async def allocate_resources(body: AllocateRequest) -> Dict[str, Any]:
    """
    Allocate emergency resources based on crisis type and severity.

    The allocator selects the most appropriate unit types for the
    reported crisis, updates internal availability counters, and
    returns estimated arrival times alongside a full inventory snapshot.

    Args:
        body (AllocateRequest): Crisis metadata from the caller.

    Returns:
        AllocateResponse: Allocation result with ETA and resource status.

    Raises:
        HTTPException 422: Automatically raised by FastAPI on schema mismatch.
        HTTPException 500: If the allocator raises an unexpected error.
    """
    _logger.write_trace(
        agent_name="allocate_endpoint",
        step_type="OBSERVE",
        reasoning=(
            f"Allocation request — crisis_type={body.crisis_type}, "
            f"severity={body.severity}, location={body.location}"
        ),
        confidence_before=0.5,
        confidence_after=0.5,
    )

    try:
        result = allocator.allocate(
            crisis_type=body.crisis_type,
            severity=body.severity,
            location=body.location,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    _logger.write_trace(
        agent_name="allocate_endpoint",
        step_type="ACT",
        reasoning=(
            f"Dispatched {result['allocated_resources']} — "
            f"ETA={result['estimated_arrival_min']} min, "
            f"coverage={result['coverage_score']}"
        ),
        confidence_before=0.5,
        confidence_after=0.9,
    )

    return result

# Project Rules for AI Agent

You are building a **CIRO Hackathon 2026** project: Fire Crisis Response System.

## Tech Stack
- **Frontend:** Flutter (Dart)
- **Backend:** FastAPI (Python 3.10+)
- **AI/ML:** YOLOv8 for fire/smoke detection
- **Database:** Firestore (or local JSON for demo)

## Coding Standards
- Always add docstrings for Python functions
- Always add comments for complex Dart widgets
- Use type hints in Python
- Use const constructors in Flutter where possible

## File Organization
- Backend code goes in `backend/` folder
- Flutter code goes in `app/lib/` folder
- Logs and traces go in `logs/demo_runs/`
- Model weights go in `models/weights/`

## Trace Logging (Critical for Hackathon)
- Every agent decision must be logged using `TraceLogger`
- Each trace entry must include: agent_name, step_type, reasoning, confidence_before, confidence_after

## Response Preferences
- Give complete code without placeholders
- Explain complex sections briefly
- Prioritize working code over perfect code
- Keep UI simple but functional

## Token Efficiency
- Do not repeat entire files unless asked
- Show only changed sections when updating files
- Keep responses concise but complete
# CIRO Fire Crisis Response System

AI-powered fire detection with agentic reasoning traces.

## Tech Stack
- Frontend: Flutter
- Backend: FastAPI
- AI: YOLOv8
- Real-time: WebSocket

## Setup

### Backend
```bash
cd backend
python -m venv venv
venv\Scripts\activate
pip install fastapi uvicorn ultralytics opencv-python
uvicorn main:app --reload
```

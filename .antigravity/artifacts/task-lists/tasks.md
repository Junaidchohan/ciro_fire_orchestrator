# CIRO Hackathon 2026: Fire Crisis Response System Task List

This document outlines the detailed plan, current status, and estimated completion times for each phase of the **Fire Crisis Response System** (ciro_fire_orchestrator).

---

## 📊 Overview Status & Timeline

| Phase | Description | Status | Est. Time | Time Spent / Remaining |
| :--- | :--- | :---: | :---: | :---: |
| **Phase 1** | Project Bootstrapping & Setup | **Completed** | 6.5 hrs | 6.5 hrs (Spent) |
| **Phase 2** | Backend APIs & WebSocket Engine | **Completed** | 5.0 hrs | 5.0 hrs (Spent) |
| **Phase 3** | YOLOv8 Classification Service | **In Progress** | 7.5 hrs | 3.5 hrs (Remaining) |
| **Phase 4** | Emergency Decision Agent (OADAE) | **In Progress** | 10.5 hrs | 5.0 hrs (Remaining) |
| **Phase 5** | Material 3 Flutter UI / App | **In Progress** | 16.5 hrs | 7.5 hrs (Remaining) |
| **Phase 6** | E2E Integration & Demo Runs | **Pending** | 8.0 hrs | 8.0 hrs (Remaining) |
| **Total** | **Whole Project Scope** | **Active** | **54.0 hrs** | **24.0 hrs (Remaining)** |

---

## 📂 Detailed Phase Breakdown

### Phase 1: Setup
> **Status:** `[x] Completed` | **Time Estimate:** 6.5 hours

- [x] **Backend Skeleton Setup:** Create directory structure `backend/{routes,agents,services,schemas,utils}`. (Est: 2h)
- [x] **Flutter Base Setup:** Initialize empty application `app/` folder using `flutter create .`. (Est: 2h)
- [x] **TraceLogger Service:** Implement a thread-safe custom `TraceLogger` class (`backend/services/trace_logger.py`) to output to `logs/demo_runs/` matching the CIRO rule constraints. (Est: 1h)
- [x] **Frontend Dependency Registration:** Configure `app/pubspec.yaml` with required modules (`http`, `google_fonts`, `camera`, `image_picker`, `firebase_core`, `cloud_firestore`) and run `flutter pub get`. (Est: 1.5h)

---

### Phase 2: Backend APIs
> **Status:** `[x] Completed` | **Time Estimate:** 5.0 hours

- [x] **FastAPI Application Core:** Setup `backend/main.py` with FastAPI instance, CORS configurations, and simple `/health` routing. (Est: 1h)
- [x] **WebSocket Alert Router:** Implement real-time broadcast engine (`backend/websocket_endpoint.py`) at `/ws` endpoint. (Est: 2h)
- [x] **Trace Endpoint:** Add asynchronous REST APIs to serve logged agent traces `/traces` back to frontend clients. (Est: 2h)

---

### Phase 3: YOLO Detection
> **Status:** `[/] In Progress` | **Time Estimate:** 7.5 hours

- [x] **YOLOv8 Service Structure:** Implement `yolo_detector.py` to handle YOLO model loading, image preprocessing, and label extraction, complete with robust mock data fallback. (Est: 2.5h)
- [x] **Detection Endpoint:** Establish `backend/routes/detect.py` to receive uploaded images, execute detection, record structured trace entries, and return JSON responses. (Est: 1.5h)
- [/] **Weights Path & Model Optimization:** Verify and configure pathing to `models/weights/` and optimize YOLOv8 startup/inference latency. (Est: 2h)
- [ ] **Detection E2E Testing:** Execute blackbox unit tests using test fire/smoke images and verify correct class output. (Est: 1.5h)

---

### Phase 4: Decision Agent
> **Status:** `[/] In Progress` | **Time Estimate:** 10.5 hours

- [x] **Multi-Stage Decision Model:** Implement core `DecisionAgent` in `backend/agents/decision_agent.py` supporting distinct `OBSERVE`, `ANALYZE`, `DECIDE`, `ACT`, and `EVALUATE` phases. (Est: 4h)
- [x] **Trace Injection:** Integrate decision steps directly with `TraceLogger` including `confidence_before` and `confidence_after`. (Est: 1.5h)
- [/] **Orchestration Logic Integration:** Wire agent reasoning flow following the rule checklist sequence: `Fusion` ➔ `Classifier` ➔ `Allocator` ➔ `Simulator`. (Est: 3h)
- [ ] **Decision Route & Trigger:** Add `/decision` post-route and tie it automatically to activate upon positive YOLOv8 fire detections. (Est: 2h)

---

### Phase 5: Flutter UI
> **Status:** `[/] In Progress` | **Time Estimate:** 16.5 hours

- [x] **Theme System:** Create dark styling guidelines inside `app/lib/theme/app_colors.dart` using a modern Material 3 custom style, gradients, and custom chip designs. (Est: 1.5h)
- [x] **Camera & Capture Screen:** Build `app/lib/screens/camera_screen.dart` with support for camera inputs, library image pickers, and POST `/detect` integrations. (Est: 3.5h)
- [x] **Trace Log Screen:** Implement high-fidelity `app/lib/screens/trace_log_screen.dart` displaying step-wise trace listings using colored agent chips, pull-to-refresh, and confidence meters. (Est: 4h)
- [/] **WebSocket Alerts Connection:** Connect frontend `AlertService` with the backend WebSocket route to trigger SnackBar alert overlays. (Est: 2h)
- [ ] **Interactive Command Dashboard:** Build an asymmetrical dashboard screen presenting live system metrics, current active fire locations, and quick actions. (Est: 3h)
- [ ] **Responsive Navigation Drawer:** Create custom UI drawer structure for fluent navigation between Dashboard, Camera Upload, and Trace Log screens. (Est: 2.5h)

---

### Phase 6: Integration
> **Status:** `[ ] Pending` | **Time Estimate:** 8.0 hours

- [ ] **Persistence Integration:** Ensure structured detections and trace outputs successfully sync to local storage/Firestore. (Est: 2.5h)
- [ ] **End-to-End Simulation Run:** Verify the complete pipeline: Camera upload ➔ YOLO trigger ➔ Decision Agent routing ➔ Real-time WebSocket SnackBar alert broadcast ➔ Flutter Trace Card updates. (Est: 4h)
- [ ] **Clean demo traces & logs generation:** Clear temporary items and write permanent demo runs to `logs/demo_runs/` for presentation. (Est: 1.5h)

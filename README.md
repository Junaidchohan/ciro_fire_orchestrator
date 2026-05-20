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
pip install fastapi uvicorn ultralytics opencv-python httpx
uvicorn main:app --reload
```

> [!NOTE]
> **API Keys & Rate Limits**
> - **Weather**: Uses Open-Meteo (no API key required). Results are cached for 5 minutes.
> - **Traffic**: Uses TomTom Traffic API. You must set the `TOMTOM_API_KEY` environment variable for real traffic data. (Get a free key at [developer.tomtom.com](https://developer.tomtom.com/)). If omitted, the system falls back to mock traffic data. Results are cached for 5 minutes to prevent rate limiting.
> - **Google Maps**: The Dashboard Screen uses Google Maps. You need to obtain an API key from the Google Cloud Console.
>   - For Android: Add your API key to `app/android/app/src/main/AndroidManifest.xml` inside the `<application>` tag: `<meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_KEY"/>`
>   - For iOS: Add your API key to `app/ios/Runner/AppDelegate.swift`: `GMSServices.provideAPIKey("YOUR_KEY")`
>   - Once configured, set `_hasGoogleMapsApiKey = true;` inside `app/lib/screens/dashboard_screen.dart` to enable the live map. Otherwise, it uses a fallback UI.

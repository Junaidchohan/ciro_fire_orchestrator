class ApiConfig {
  // Use Google Cloud Run (LIVE)
  static const String baseUrl =
      'https://anti-gravity-backend-284125878879.us-central1.run.app';

  // Endpoints
  static const String detect = '$baseUrl/detect';
  static const String health = '$baseUrl/health';
  static const String traces = '$baseUrl/traces';
  static const String history = '$baseUrl/history';
  static const String productionStart = '$baseUrl/production/start';
  static const String productionStop = '$baseUrl/production/stop';
  static const String simulate = '$baseUrl/simulate';
  static const String allocate = '$baseUrl/allocate';

  // WebSocket (fix this - HTTPS uses WSS, not WS)
  static const String wsUrl =
      'wss://anti-gravity-backend-284125878879.us-central1.run.app/ws';
}

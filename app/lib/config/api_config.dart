class ApiConfig {
  // 1. Comment out the Cloud Run URL
  // static const String baseUrl = 'https://anti-gravity-backend-284125878879.us-central1.run.app';

  // 2. Uncomment the local URL
  static const String baseUrl = 'http://172.16.2.66:8000';

  static const String detect = '$baseUrl/detect';
  static const String detectVideo = '$baseUrl/detect_video';
  static const String health = '$baseUrl/health';
  static const String traces = '$baseUrl/traces';
  static const String history = '$baseUrl/history';
  static const String productionStart = '$baseUrl/production/start';
  static const String productionStop = '$baseUrl/production/stop';
  static const String simulate = '$baseUrl/simulate';
  static const String allocate = '$baseUrl/allocate';

  // 3. Make sure WebSocket points to local too (use ws://, not wss:// for local)
  static const String wsUrl = 'ws://172.16.2.66:8000/ws';
}

class ApiConfig {
  static const String baseUrl = 'https://ciro-fire-orchestrator.onrender.com';
  static const String detect = '$baseUrl/detect';
  static const String health = '$baseUrl/health';
  static const String traces = '$baseUrl/traces';
  static const String history = '$baseUrl/history';
  static const String productionStart = '$baseUrl/production/start';
  static const String productionStop = '$baseUrl/production/stop';
  static const String simulate = '$baseUrl/simulate';
  static const String allocate = '$baseUrl/allocate';
  static const String wsUrl = 'wss://ciro-fire-orchestrator.onrender.com/ws';
}

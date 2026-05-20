import 'dart:convert';
import 'dart:io';

class WebSocketService {
  WebSocket? _socket;

  Future<void> connect(Function(Map<String, dynamic>) onEvent) async {
    try {
      _socket = await WebSocket.connect('ws://localhost:8000/ws');
      _socket!.listen((message) {
        if (message is String) {
          try {
            final data = jsonDecode(message);
            onEvent(data);
          } catch (_) {}
        }
      });
    } catch (e) {
      print('WebSocket connection error: $e');
    }
  }

  void disconnect() {
    _socket?.close();
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';

class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  WebSocketChannel? _channel;
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);

  void Function(Map<String, dynamic> alertData)? onAlertReceived;

  void connect() {
    if (isConnected.value) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(ApiConfig.wsUrl));

      isConnected.value = true;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (onAlertReceived != null) {
              onAlertReceived!(data);
            }
          } catch (e) {
            debugPrint("Error parsing alert message: $e");
          }
        },
        onDone: () {
          isConnected.value = false;
          _reconnect();
        },
        onError: (error) {
          isConnected.value = false;
          _reconnect();
        },
      );
    } catch (e) {
      isConnected.value = false;
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!isConnected.value) {
        connect();
      }
    });
  }

  void disconnect() {
    _channel?.sink.close();
    isConnected.value = false;
  }
}

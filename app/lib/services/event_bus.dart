import 'dart:async';

/// Base event class
class CrisisEvent {
  final String? crisisId;
  CrisisEvent({this.crisisId});
}

/// Specific event fired when a new crisis is detected.
class CrisisDetectedEvent extends CrisisEvent {
  CrisisDetectedEvent({super.crisisId});
}

/// Global event bus to broadcast messages across the app.
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _controller = StreamController<CrisisEvent>.broadcast();

  /// Raw stream of all events.
  Stream<CrisisEvent> get stream => _controller.stream;

  /// Returns a typed stream filtered to events of type [T].
  /// Usage: EventBus().on<CrisisDetectedEvent>().listen(...)
  Stream<T> on<T extends CrisisEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  /// Fires [event] to all listeners.
  void fire(CrisisEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

// Stub implementation for non-web platforms.
// On native, video_player handles playback; this file is never really called
// but must exist to satisfy the conditional import in monitor_screen.dart.
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Stub class — methods are no-ops on native platforms.
class WebVideoHelper {
  /// No-op on native — returns an empty string.
  static String createBlobUrl(Uint8List bytes, String mimeType) => '';

  /// No-op on native.
  static void revokeBlobUrl(String url) {}

  /// Should never be called on native; returns an empty widget.
  static Widget buildVideoWidget(String blobUrl) => const SizedBox.shrink();
}

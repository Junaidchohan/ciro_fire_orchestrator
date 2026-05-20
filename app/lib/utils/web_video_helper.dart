// Web-specific video helper using dart:html and ui_web.
// This file is only compiled on web via conditional import.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Web-specific helper for creating blob URLs for video playback
/// and rendering them as native <video> elements via HtmlElementView.
class WebVideoHelper {
  static final Set<String> _registeredViewTypes = {};

  /// Creates a blob URL from raw [bytes] with the given [mimeType].
  /// Call [revokeBlobUrl] when the URL is no longer needed.
  static String createBlobUrl(Uint8List bytes, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    return html.Url.createObjectUrl(blob);
  }

  /// Revokes a previously created blob URL to free browser memory.
  static void revokeBlobUrl(String url) {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  }

  /// Returns a Flutter widget that renders a native HTML <video> element
  /// for the given [blobUrl]. The video is auto-played and looped.
  static Widget buildVideoWidget(String blobUrl) {
    final viewType = 'ciro-video-${blobUrl.hashCode.abs()}';
    if (!_registeredViewTypes.contains(viewType)) {
      _registeredViewTypes.add(viewType);
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
        final video = html.VideoElement()
          ..src = blobUrl
          ..autoplay = true
          ..loop = true
          ..controls = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.backgroundColor = 'black';
        return video;
      });
    }
    return SizedBox.expand(
      child: HtmlElementView(viewType: viewType),
    );
  }
}

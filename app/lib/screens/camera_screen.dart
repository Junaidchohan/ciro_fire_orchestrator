import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Uint8List? _selectedImageBytes;
  String _result = '';
  bool _loading = false;
  html.MediaStream? _mediaStream;
  html.VideoElement? _videoElement;
  bool _cameraReady = false;

  // Severity state from last detection
  String? _severity;          // 'low' | 'medium' | 'high' | 'none' | null
  String? _recommendation;    // 'monitor' | 'prepare' | 'evacuate' | 'none'
  bool _detected = false;
  double _confidence = 0.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices?.getUserMedia({
        'video': true,
      });
      if (stream != null) {
        _mediaStream = stream;
        _videoElement = html.VideoElement()
          ..srcObject = stream
          ..autoplay = true
          ..playsInline = true
          ..style.width = '100%'
          ..style.height = 'auto';

        ui_web.platformViewRegistry.registerViewFactory(
          _videoElement!.tagName,
          (int viewId) => _videoElement!,
        );

        await _videoElement!.onCanPlay.first;
        _videoElement!.play();
        setState(() => _cameraReady = true);
      }
    } catch (e) {
      print('Camera init failed: $e');
    }
  }

  void _captureFrame() {
    if (_videoElement == null) return;

    final canvas = html.CanvasElement()
      ..width = _videoElement!.videoWidth
      ..height = _videoElement!.videoHeight;

    canvas.context2D.drawImage(_videoElement!, 0, 0);
    final dataUri = canvas.toDataUrl('image/png');
    final base64 = dataUri.split(',')[1];
    final bytes = html.window.atob(base64).codeUnits.toList();

    setState(() {
      _selectedImageBytes = Uint8List.fromList(bytes);
      _result = '';
      _severity = null;
      _recommendation = null;
      _detected = false;
      _confidence = 0.0;
    });
  }

  void _pickImage() {
    final input = html.FileUploadInputElement();
    input.accept = 'image/*';
    input.click();
    input.onChange.listen((e) async {
      final file = input.files!.first;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      setState(() {
        _selectedImageBytes = Uint8List.fromList(reader.result as List<int>);
        _result = '';
        _severity = null;
        _recommendation = null;
        _detected = false;
        _confidence = 0.0;
      });
    });
  }

  Future<void> _detectFire() async {
    if (_selectedImageBytes == null) return;
    setState(() => _loading = true);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:8000/detect'),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _selectedImageBytes!,
          filename: 'image.jpg',
        ),
      );
      var response = await request.send();
      var result = json.decode(await response.stream.bytesToString());

      setState(() {
        _detected = result['detected'] == true;
        _confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
        _severity = (result['severity'] as String?) ?? 'none';
        _recommendation = (result['recommendation'] as String?) ?? 'none';
        _result = _detected
            ? '🔥 FIRE DETECTED! ${(_confidence * 100).toStringAsFixed(1)}%'
            : '✅ No fire detected';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Builds the severity badge, alert message, and action recommendation panel.
  Widget _buildResultPanel() {
    if (!_detected) {
      // No fire detected – plain success card
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.shade800.withOpacity(0.3),
          border: Border.all(color: Colors.green, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No fire detected. Area is clear.',
                style: TextStyle(fontSize: 15, color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    // Severity-specific config
    final String sev = _severity ?? 'low';
    final Color badgeColor;
    final Color panelBorder;
    final String alertMsg;
    final String action;
    final IconData actionIcon;

    switch (sev) {
      case 'high':
        badgeColor = Colors.red;
        panelBorder = Colors.red;
        alertMsg = '⚠️ CRITICAL – Fire confirmed at HIGH confidence!';
        action = 'EVACUATE IMMEDIATELY';
        actionIcon = Icons.directions_run;
        break;
      case 'medium':
        badgeColor = Colors.orange;
        panelBorder = Colors.orange;
        alertMsg = '🟠 WARNING – Significant fire risk detected.';
        action = 'PREPARE FOR EVACUATION';
        actionIcon = Icons.warning_amber_rounded;
        break;
      default: // 'low'
        badgeColor = Colors.amber;
        panelBorder = Colors.amber;
        alertMsg = '🟡 ALERT – Low-level fire/smoke trace detected.';
        action = 'MONITOR CLOSELY';
        actionIcon = Icons.visibility;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelBorder.withOpacity(0.12),
        border: Border.all(color: panelBorder, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon + title + badge
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fire Detected',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              // Severity badge chip
              Chip(
                label: Text(
                  sev.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                backgroundColor: badgeColor,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Alert message
          Text(alertMsg, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
          // Recommended action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(actionIcon, color: badgeColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recommended: $action',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fire Detection'),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Camera preview
            Container(
              height: 280,
              width: double.infinity,
              color: Colors.black,
              child: _cameraReady && _videoElement != null
                  ? HtmlElementView(viewType: _videoElement!.tagName)
                  // This already works once ui is imported
                  : Center(
                      child: Text(
                        'Camera loading...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
            SizedBox(height: 12),

            // Buttons row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _captureFrame,
                    icon: Icon(Icons.camera),
                    label: Text('Capture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: Icon(Icons.photo_library),
                    label: Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Captured image preview
            if (_selectedImageBytes != null)
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
              ),
            SizedBox(height: 16),

            // Detect button
            ElevatedButton(
              onPressed: _detectFire,
              child: Text('DETECT FIRE', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Colors.red,
              ),
            ),
            if (_loading)
              SizedBox(height: 16, child: CircularProgressIndicator()),
            if (_result.isNotEmpty) SizedBox(height: 16),
            if (_result.isNotEmpty) _buildResultPanel(),
            // Confidence indicator
            if (_result.isNotEmpty)
              Column(
                children: [
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Confidence: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${(_confidence * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                  SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _confidence,
                    backgroundColor: Colors.grey[300],
                    color: _confidence > 0.7 ? Colors.red : (_confidence > 0.4 ? Colors.orange : Colors.green),
                    minHeight: 10,
                  ),
                  SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _confidence),
                    duration: Duration(milliseconds: 500),
                    builder: (context, value, child) => Text(
                      '${(value * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // ── Severity badge pill (user-specified) ──────────────────
                  if (_severity != null && _severity != 'none') ...([
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _severity == 'high'
                            ? Colors.red
                            : (_severity == 'medium' ? Colors.orange : Colors.yellow),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _severity?.toUpperCase() ?? 'UNKNOWN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

extension on html.VideoElement {
  set playsInline(bool playsInline) {}
}

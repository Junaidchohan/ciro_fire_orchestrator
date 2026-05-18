import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

class LiveCameraScreen extends StatefulWidget {
  @override
  _LiveCameraScreenState createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;
  bool _cameraReady = false;
  Uint8List? _capturedImage;
  String _result = '';
  bool _loading = false;
  final String _viewType = 'live-video-element';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({'video': true});
      _mediaStream = stream;
      _videoElement = html.VideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%';
      _videoElement!.setAttribute('playsinline', 'true');
      
      // Register view factory for HtmlElementView
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => _videoElement!,
      );
      
      await _videoElement!.onCanPlay.first;
      _videoElement!.play();
      
      setState(() => _cameraReady = true);
    } catch (e) {
      print('Camera error: $e');
    }
  }

  void _captureImage() {
    if (_videoElement == null) return;
    
    final canvas = html.CanvasElement()
      ..width = _videoElement!.videoWidth
      ..height = _videoElement!.videoHeight;
    
    canvas.context2D.drawImage(_videoElement!, 0, 0);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.8);
    final bytes = dataUrl.split(',')[1];
    final imageBytes = html.window.atob(bytes).codeUnits.toList();
    
    setState(() {
      _capturedImage = Uint8List.fromList(imageBytes);
      _result = '';
    });
  }

  Future<void> _detectFire() async {
    if (_capturedImage == null) return;
    setState(() => _loading = true);
    
    try {
      var request = http.MultipartRequest('POST', Uri.parse(ApiConfig.detect));
      request.files.add(http.MultipartFile.fromBytes('image', _capturedImage!, filename: 'capture.jpg'));
      var response = await request.send();
      var result = json.decode(await response.stream.bytesToString());
      
      setState(() {
        _result = result['detected'] 
          ? '🔥 FIRE DETECTED! ${(result['confidence'] * 100).toStringAsFixed(1)}%' 
          : '✅ No fire detected';
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live Camera'), backgroundColor: Colors.red),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: _cameraReady && _videoElement != null
                  ? HtmlElementView(viewType: _viewType)
                  : Center(child: CircularProgressIndicator()),
            ),
          ),
          if (_capturedImage != null)
            Container(
              height: 100,
              margin: EdgeInsets.all(8),
              child: Image.memory(_capturedImage!),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _captureImage,
                  child: Text('CAPTURE'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: _detectFire,
                  child: Text('DETECT'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ),
            ],
          ),
          if (_loading) CircularProgressIndicator(),
          if (_result.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(_result, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

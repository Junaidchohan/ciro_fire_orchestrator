import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

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
        _result = result['detected']
            ? '🔥 FIRE DETECTED! ${(result['confidence'] * 100).toStringAsFixed(1)}%'
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
            if (_result.isNotEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _result.contains('FIRE')
                      ? Colors.red.shade100
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _result,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
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

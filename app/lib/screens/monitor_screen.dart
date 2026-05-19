import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import '../config/api_config.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../theme/app_colors.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  // Camera State
  html.MediaStream? _mediaStream;
  html.VideoElement? _videoElement;
  bool _cameraReady = false;

  // Detection State
  bool _loading = false;
  bool _isAutoMonitoring = false;
  bool _isMonitoringActive = false;
  Timer? _autoMonitorTimer;
  Uint8List? _selectedImageBytes;
  
  // Results
  bool _detected = false;
  String _crisisType = 'None';
  double _confidence = 0.0;
  String _severity = 'none'; // 'low' | 'medium' | 'high' | 'none'
  String _recommendation = 'none';

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
          ..style.height = '100%'
          ..style.objectFit = 'cover';

        ui_web.platformViewRegistry.registerViewFactory(
          _videoElement!.tagName,
          (int viewId) => _videoElement!,
        );

        await _videoElement!.onCanPlay.first;
        _videoElement!.play();
        if (mounted) setState(() => _cameraReady = true);
      }
    } catch (e) {
      print('Camera init failed: $e');
    }
  }

  void _toggleAutoMonitoring() {
    setState(() {
      _isAutoMonitoring = !_isAutoMonitoring;
      _isMonitoringActive = _isAutoMonitoring;
    });

    if (_isAutoMonitoring) {
      _autoMonitorTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (!_loading) _captureAndDetect();
      });
    } else {
      _autoMonitorTimer?.cancel();
    }
  }

  Future<void> _captureAndDetect() async {
    if (_videoElement == null) return;

    final canvas = html.CanvasElement()
      ..width = _videoElement!.videoWidth
      ..height = _videoElement!.videoHeight;

    canvas.context2D.drawImage(_videoElement!, 0, 0);
    final dataUri = canvas.toDataUrl('image/jpeg', 0.8);
    final base64 = dataUri.split(',')[1];
    final bytes = html.window.atob(base64).codeUnits.toList();

    _selectedImageBytes = Uint8List.fromList(bytes);
    await _detectCrisis();
  }

  void _pickImage() {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    input.onChange.listen((e) async {
      final file = input.files!.first;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      setState(() {
        _isMonitoringActive = true;
        _selectedImageBytes = Uint8List.fromList(reader.result as List<int>);
      });
      _detectCrisis().then((_) {
        if (mounted) {
          setState(() {
            _isMonitoringActive = _isAutoMonitoring;
          });
        }
      });
    });
  }

  Future<void> _detectCrisis() async {
    if (_selectedImageBytes == null) return;
    if (!_isMonitoringActive) return;
    print("Detection request sent at ${DateTime.now()}");
    setState(() => _loading = true);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.detect),
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

      if (mounted) {
        setState(() {
          _detected = result['detected'] == true;
          _confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
          _severity = (result['severity'] as String?) ?? 'none';
          _recommendation = (result['recommendation'] as String?) ?? 'none';
          _crisisType = (result['crisis_type'] as String?)?.toUpperCase() ?? (_detected ? 'FIRE' : 'NONE');
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _autoMonitorTimer?.cancel();
    _mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder(
            tween: ColorTween(begin: Colors.green.shade300, end: Colors.green.shade600),
            duration: const Duration(milliseconds: 1000),
            builder: (context, Color? color, child) {
              return Icon(Icons.circle, size: 12, color: color);
            },
            onEnd: () {
              // Note: A true pulsing effect requires an AnimationController, using a simple static color for now or rely on Tween.
            },
          ),
          const SizedBox(width: 8),
          Text(
            'CIRO ACTIVE',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.2,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    Color badgeColor = AppColors.success;
    IconData crisisIcon = Icons.check_circle;
    
    if (_detected) {
      switch (_severity) {
        case 'high':
          badgeColor = AppColors.error;
          crisisIcon = Icons.warning;
          break;
        case 'medium':
          badgeColor = AppColors.secondary;
          crisisIcon = Icons.warning_amber;
          break;
        default:
          badgeColor = AppColors.warning;
          crisisIcon = Icons.info_outline;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(crisisIcon, color: badgeColor, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    _detected ? '$_crisisType DETECTED' : 'AREA CLEAR',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (_detected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    _severity.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Confidence Level',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${(_confidence * 100).toStringAsFixed(1)}%',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _confidence,
              backgroundColor: AppColors.background,
              color: badgeColor,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Action',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _detected ? _recommendation.toUpperCase() : 'MONITOR NORMALLY',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBanner(),
              
              // Camera Preview
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraReady && _videoElement != null)
                      HtmlElementView(viewType: _videoElement!.tagName)
                    else
                      const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    if (_loading)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildResultCard(),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleAutoMonitoring,
                      icon: Icon(_isAutoMonitoring ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isAutoMonitoring ? 'STOP MONITORING' : 'START MONITORING',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isAutoMonitoring ? AppColors.textSecondary : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        'UPLOAD IMAGE',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on html.VideoElement {
  set playsInline(bool playsInline) {}
}

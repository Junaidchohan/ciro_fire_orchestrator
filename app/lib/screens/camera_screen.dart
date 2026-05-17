import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _detectionResult;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      } else {
        setState(() {
          _errorMessage = "No cameras available on this device.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Camera initialization failed. Use Gallery instead.";
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndUpload() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _detectionResult = null;
      });

      final XFile image = await _controller!.takePicture();
      await _uploadImage(image);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error capturing photo: $e";
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _detectionResult = null;
      });

      await _uploadImage(image);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error picking image: $e";
      });
    }
  }

  Future<void> _uploadImage(XFile image) async {
    try {
      // NOTE: Using localhost. In Android emulator use 10.0.2.2:8000
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/detect'),
      );
      
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _detectionResult = json.decode(responseData);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Upload failed with status ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Upload failed: $e";
        _isLoading = false;
      });
    }
  }

  Widget _buildDetectionResult() {
    if (_detectionResult == null) return const SizedBox.shrink();

    final detection = _detectionResult!['detection'] ?? {};
    final bool isFire = detection['detected'] ?? false;
    final double confidence = (detection['confidence'] ?? 0.0).toDouble();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFire ? AppColors.error : AppColors.success,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFire ? Icons.local_fire_department : Icons.check_circle,
                color: isFire ? AppColors.error : AppColors.success,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                isFire ? 'FIRE DETECTED' : 'ALL CLEAR',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isFire ? AppColors.error : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          if (detection['mock'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                '// mock: result generated by fallback logic',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
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
      appBar: AppBar(
        title: Text(
          'Live Detection',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.appBarGradient,
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceElevated, width: 2),
              ),
              clipBehavior: Clip.hardEdge,
              child: _isCameraInitialized
                  ? CameraPreview(_controller!)
                  : Center(
                      child: Text(
                        _errorMessage ?? 'Initializing camera...',
                        style: GoogleFonts.outfit(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          if (_errorMessage != null && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.outfit(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          _buildDetectionResult(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading || !_isCameraInitialized ? null : _captureAndUpload,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({Key? key}) : super(key: key);

  @override
  _LiveCameraScreenState createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen> {
  // Camera State
  html.VideoElement? _videoElement;
  html.MediaStream? _mediaStream;
  bool _cameraReady = false;
  Uint8List? _capturedImage;
  bool _loading = false;
  final String _viewType = 'live-video-element';

  // --- NEW: Antigravity Context State ---
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(
    text: "G-10, Islamabad",
  );
  bool _testMode = false;

  // Detection Results State
  bool _detected = false;
  double _confidence = 0.0;
  String _severity = 'none';
  String _recommendation = 'none';
  String _crisisType = 'NONE';

  // --- NEW: Antigravity Orchestration State ---
  String? _currentCrisisId;
  Map<String, dynamic>? _allocationPlan;
  Map<String, dynamic>? _simulation;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': true,
      });
      _mediaStream = stream;
      _videoElement = html.VideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      _videoElement!.setAttribute('playsinline', 'true');

      // Register view factory for HtmlElementView
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => _videoElement!,
      );

      await _videoElement!.onCanPlay.first;
      _videoElement!.play();

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
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
      _resetResults();
    });
  }

  void _resetResults() {
    _detected = false;
    _confidence = 0.0;
    _severity = 'none';
    _recommendation = 'none';
    _allocationPlan = null;
    _simulation = null;
    _currentCrisisId = null;
  }

  Future<void> _detectFire() async {
    if (_capturedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture an image first.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse(ApiConfig.detect));
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _capturedImage!,
          filename: 'capture.jpg',
        ),
      );

      // --- NEW: Attach Contextual Data for Antigravity ---
      if (_socialController.text.isNotEmpty) {
        request.fields['social_text'] = _socialController.text;
      }

      if (_locationController.text.toLowerCase().contains("islamabad")) {
        request.fields['lat'] = "33.6844";
        request.fields['lon'] = "73.0479";
      } else {
        request.fields['lat'] = "31.5204"; // Lahore fallback
        request.fields['lon'] = "74.3587";
      }
      request.fields['test_mode'] = _testMode.toString();

      var response = await request.send();
      var result = json.decode(await response.stream.bytesToString());

      if (mounted) {
        setState(() {
          _detected = result['detected'] == true;
          _confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
          _severity = (result['severity'] as String?) ?? 'none';
          _recommendation = (result['action'] as String?) ?? 'none';
          _crisisType =
              (result['crisis_type'] as String?)?.toUpperCase() ??
              (_detected ? 'FIRE' : 'NONE');

          // Parse Antigravity Results
          _currentCrisisId = result['crisis_id'];
          _allocationPlan = result['allocation_plan'];
          _simulation = result['simulation'];

          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // --- NEW: False Alarm Logic ---
  Future<void> _simulateFalseAlarm() async {
    if (_currentCrisisId == null) return;

    try {
      final url = '${ApiConfig.baseUrl}/retract_crisis/$_currentCrisisId';
      final response = await http.post(Uri.parse(url));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛑 False alarm recorded. Resources retracted.'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() {
          _resetResults();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to retract crisis: $e')));
    }
  }

  @override
  void dispose() {
    _mediaStream?.getTracks().forEach((track) => track.stop());
    _socialController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // --- UI COMPONENTS ---

  Widget _buildContextControls() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
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
          Text(
            'Multi-Signal Context (Antigravity)',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _socialController,
            decoration: InputDecoration(
              hintText: 'Social Text (e.g., "Huge fire spreading!")',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              hintText: 'Location (e.g., G-10, Islamabad)',
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          SwitchListTile(
            title: Text(
              'Test Mode (Simulate Low Confidence)',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textMain,
              ),
            ),
            contentPadding: EdgeInsets.zero,
            value: _testMode,
            activeColor: AppColors.primary,
            onChanged: (val) => setState(() => _testMode = val),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    Color badgeColor = AppColors.success;
    IconData crisisIcon = Icons.check_circle;

    if (_detected) {
      switch (_severity) {
        case 'high':
          badgeColor = AppColors.error;
          crisisIcon = Icons.warning;
          break;
        case 'medium':
          badgeColor = AppColors.warning;
          crisisIcon = Icons.warning_amber;
          break;
        default:
          badgeColor = AppColors.secondary ?? Colors.amber;
          crisisIcon = Icons.info_outline;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary Status Card
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _detected
                  ? badgeColor.withOpacity(0.4)
                  : AppColors.success.withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
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
                          color: AppColors.textMain,
                        ),
                      ),
                    ],
                  ),
                  if (_detected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
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
                      color: AppColors.textMain,
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
              Text(
                'Action: ${_recommendation.toUpperCase()}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ],
          ),
        ),

        // Antigravity Expansion Tile
        if (_detected && _allocationPlan != null)
          Card(
            elevation: 0,
            color: AppColors.surface,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(
                'Antigravity Orchestration',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textMain,
                ),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                if (_allocationPlan!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Allocated Units: ${_allocationPlan!.entries.map((e) => "${e.value}x ${e.key}").join(', ')}',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_simulation != null &&
                    _simulation!['traffic_reroute'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Simulation: ${_simulation!['traffic_reroute']['estimated_congestion_reduction']} congestion reduction.',
                      style: GoogleFonts.outfit(color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),

        // False Alarm Retraction Button
        if (_testMode && _detected)
          OutlinedButton.icon(
            onPressed: _simulateFalseAlarm,
            icon: const Icon(Icons.block, color: AppColors.error),
            label: const Text(
              'Simulate False Alarm',
              style: TextStyle(color: AppColors.error),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Live Camera Monitor',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Camera feed
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _cameraReady && _videoElement != null
                  ? HtmlElementView(viewType: _viewType)
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),
            const SizedBox(height: 16),

            // Captured Image Preview
            if (_capturedImage != null) ...[
              Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(_capturedImage!, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
            ],

            // Context Form
            _buildContextControls(),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _captureImage,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      'CAPTURE',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _detectFire,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.analytics),
                    label: Text(
                      _loading ? 'ANALYZING' : 'DETECT',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Results Panel
            if (_confidence > 0 || _detected) _buildResultPanel(),
          ],
        ),
      ),
    );
  }
}

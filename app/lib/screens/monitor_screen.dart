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

  // --- NEW: Antigravity Context State ---
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _latController = TextEditingController(text: "33.6844");
  final TextEditingController _lonController = TextEditingController(text: "73.0479");
  bool _testMode = false;

  // Results
  bool _detected = false;
  String _crisisType = 'None';
  double _confidence = 0.0;
  String _severity = 'none';
  String _recommendation = 'none';

  // --- NEW: Antigravity Results State ---
  String? _currentCrisisId;
  Map<String, dynamic>? _allocationPlan;
  Map<String, dynamic>? _simulation;
  List<dynamic>? _notifications;

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

    setState(() {
      _loading = true;
      _allocationPlan = null; // Clear previous results
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse(ApiConfig.detect));

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _selectedImageBytes!,
          filename: 'image.jpg',
        ),
      );

      // --- NEW: Attach Contextual Data for Antigravity Engine ---
      if (_socialController.text.isNotEmpty) {
        request.fields['social_text'] = _socialController.text;
      }
      request.fields['lat'] = _latController.text;
      request.fields['lon'] = _lonController.text;
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

          // --- NEW: Parse Antigravity Results ---
          _currentCrisisId = result['crisis_id'];
          _allocationPlan = result['allocation_plan'];
          _simulation = result['simulation'];
          _notifications = result['notifications'];

          _loading = false;
        });

        // After detection, show simulation results and notifications in a bottom sheet
        if (_detected && (_simulation != null || _notifications != null)) {
          _showOrchestrationBottomSheet();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // --- NEW: False Alarm Logic ---
  Future<void> _simulateFalseAlarm() async {
    if (_currentCrisisId == null) return;

    try {
      // Assuming you added a retract endpoint to ApiConfig, else hardcode URL
      final url = '${ApiConfig.baseUrl}/retract_crisis/$_currentCrisisId';
      final response = await http.post(Uri.parse(url));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🛑 False alarm recorded and resources retracted.'),
            backgroundColor: AppColors.primary,
          ),
        );
        setState(() {
          _detected = false;
          _allocationPlan = null;
          _currentCrisisId = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to retract crisis: $e')));
    }
  }

  // --- NEW: Orchestration Bottom Sheet ---
  void _showOrchestrationBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Header with styling
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Orchestration Results',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 12),

                // Simulation Card
                if (_simulation != null) ...[
                  Text(
                    'Simulation Predictions',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSimulationRow(
                          Icons.timer, 
                          'ETA Reduction', 
                          '${_simulation!['eta_reduction_minutes'] ?? 0} mins'
                        ),
                        const SizedBox(height: 8),
                        _buildSimulationRow(
                          Icons.alt_route, 
                          'Traffic Reroute', 
                          (_simulation!['traffic_reroute'] == true || (_simulation!['traffic_reroute'] is Map && _simulation!['traffic_reroute'] != null)) ? 'Active' : 'Inactive'
                        ),
                        if (_simulation!['traffic_reroute'] is Map && _simulation!['traffic_reroute']['estimated_congestion_reduction'] != null) ...[
                          const SizedBox(height: 8),
                          _buildSimulationRow(
                            Icons.trending_down,
                            'Congestion Reduction',
                            '${_simulation!['traffic_reroute']['estimated_congestion_reduction']}'
                          ),
                        ],
                        const SizedBox(height: 8),
                        _buildSimulationRow(
                          Icons.report_problem_outlined, 
                          'Side Effects', 
                          '${_simulation!['side_effects'] ?? 'None'}'
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Notifications Card
                if (_notifications != null && _notifications!.isNotEmpty) ...[
                  Text(
                    'Broadcast Notifications',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._notifications!.map((n) {
                    final target = (n['target'] as String?) ?? 'public';
                    final message = (n['message'] as String?) ?? '';
                    
                    IconData targetIcon = Icons.notifications;
                    Color targetColor = AppColors.primary;
                    if (target == 'public') {
                      targetIcon = Icons.campaign;
                      targetColor = Colors.orange;
                    } else if (target == 'hospital') {
                      targetIcon = Icons.local_hospital;
                      targetColor = Colors.red;
                    } else if (target == 'utility') {
                      targetIcon = Icons.electrical_services;
                      targetColor = Colors.blue;
                    } else if (target == 'command_center') {
                      targetIcon = Icons.security;
                      targetColor = Colors.purple;
                    }

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: AppColors.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: targetColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(targetIcon, color: targetColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    target.toUpperCase(),
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: targetColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message,
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimulationRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _autoMonitorTimer?.cancel();
    _mediaStream?.getTracks().forEach((track) => track.stop());
    _socialController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  // --- UI BUILDERS ---

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
          Icon(Icons.circle, size: 12, color: Colors.green.shade500),
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

  // --- NEW: Context Controls Form ---
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Latitude',
                    hintText: '33.6844',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lonController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Longitude',
                    hintText: '73.0479',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: Text(
              'Test Mode (Simulate Low Confidence)',
              style: GoogleFonts.outfit(fontSize: 14),
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
          badgeColor = AppColors.secondary ?? Colors.orange;
          crisisIcon = Icons.warning_amber;
          break;
        default:
          badgeColor = AppColors.warning;
          crisisIcon = Icons.info_outline;
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _detected
                  ? badgeColor.withOpacity(0.3)
                  : Colors.transparent,
            ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
              Text(
                'Recommended Action: ${_recommendation.toUpperCase()}',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // --- NEW: View Orchestration Details Button ---
        if (_detected && (_simulation != null || _notifications != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showOrchestrationBottomSheet,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('View Orchestration Details'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

        // --- NEW: False Alarm Button (Visible in Test Mode when crisis detected) ---
        if (_testMode && _detected)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
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
            ),
          ),
      ],
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
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
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

              // --- NEW: Render Context Controls ---
              _buildContextControls(),

              if (_detected || _loading) _buildResultCard(),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleAutoMonitoring,
                      icon: Icon(
                        _isAutoMonitoring ? Icons.stop : Icons.play_arrow,
                      ),
                      label: Text(
                        _isAutoMonitoring
                            ? 'STOP MONITORING'
                            : 'START MONITORING',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isAutoMonitoring
                            ? AppColors.textSecondary
                            : AppColors.primary,
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
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        'UPLOAD IMAGE',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
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

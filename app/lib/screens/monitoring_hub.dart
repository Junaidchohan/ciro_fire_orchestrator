import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// --- Configuration & Theming ---
class ApiConfig {
  static const String baseUrl =
      'http://10.0.2.2:8000'; // Use 10.0.2.2 for Android emulator, or your Cloud Run URL
  static const String detect = '$baseUrl/detect';
  static const String verifyCrisis = '$baseUrl/verify_crisis';
}

class AppColors {
  static const Color primary = Color(0xFFD32F2F); // CIRO Red
  static const Color background = Color(0xFFF5F5F7);
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF1D1D1F);
  static const Color textSecondary = Color(0xFF86868B);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color info = Color(0xFF007AFF);
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({Key? key}) : super(key: key);

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  // --- State ---
  File? _selectedImage;
  bool _isDetecting = false;
  bool _testMode = false;
  Map<String, dynamic>? _detectionResult;
  String? _currentCrisisId;

  // --- Controllers ---
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(
    text: "G-10, Islamabad",
  );

  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _socialController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // --- Helpers ---
  Map<String, String> _getLatLonFromLocation(String locationString) {
    // Simple mock geocoder based on string matching
    final loc = locationString.toLowerCase();
    if (loc.contains("islamabad")) {
      return {"lat": "33.6844", "lon": "73.0479"};
    } else if (loc.contains("karachi")) {
      return {"lat": "24.8607", "lon": "67.0011"};
    } else {
      return {"lat": "31.5204", "lon": "74.3587"}; // Default Lahore
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _detectionResult = null; // Clear previous results on new image
      });
    }
  }

  // --- API Calls ---
  Future<void> _runDetection() async {
    if (_selectedImage == null) {
      _showSnackBar(
        'Please select or capture an image first.',
        AppColors.warning,
      );
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectionResult = null;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse(ApiConfig.detect));

      // 1. Attach Image
      request.files.add(
        await http.MultipartFile.fromPath('image', _selectedImage!.path),
      );

      // 2. Attach Contextual Fields
      if (_socialController.text.isNotEmpty) {
        request.fields['social_text'] = _socialController.text;
      }

      final coords = _getLatLonFromLocation(_locationController.text);
      request.fields['lat'] = coords['lat']!;
      request.fields['lon'] = coords['lon']!;
      request.fields['test_mode'] = _testMode.toString();

      // 3. Send and Await
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _detectionResult = data;
          _currentCrisisId = data['crisis_id'];
        });
      } else {
        _showSnackBar(
          'Server Error: ${response.statusCode}',
          AppColors.primary,
        );
      }
    } catch (e) {
      _showSnackBar('Connection failed: $e', AppColors.primary);
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<void> _simulateFalseAlarm() async {
    if (_currentCrisisId == null) return;

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.verifyCrisis),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"crisis_id": _currentCrisisId, "verified": false}),
      );

      if (response.statusCode == 200) {
        _showSnackBar(
          '🛑 False alarm recorded and retracted.',
          AppColors.textMain,
        );
        setState(() {
          _detectionResult = null; // Clear screen after retraction
          _currentCrisisId = null;
        });
      }
    } catch (e) {
      _showSnackBar('Failed to retract crisis: $e', AppColors.primary);
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --- UI Builders ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'CIRO Operations',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageUploader(),
              const SizedBox(height: 20),
              _buildContextControls(),
              const SizedBox(height: 24),
              _buildDetectButton(),
              const SizedBox(height: 24),
              if (_detectionResult != null) _buildResultsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageUploader() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _selectedImage != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_selectedImage!, fit: BoxFit.cover),
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _selectedImage = null),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.satellite_alt_outlined,
                  color: AppColors.textSecondary,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Upload Incident Imagery',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textMain,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.background,
                        foregroundColor: AppColors.textMain,
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildContextControls() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              'Incident Context',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _socialController,
              decoration: InputDecoration(
                hintText: 'Describe crisis (e.g., flash flood in G-10)',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.background,
                prefixIcon: const Icon(
                  Icons.chat_bubble_outline,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: 'Location (e.g., G-10, Islamabad)',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.background,
                prefixIcon: const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          SwitchListTile(
            title: const Text(
              'Test Mode',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Flags logs as test data',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            value: _testMode,
            activeColor: AppColors.primary,
            onChanged: (val) => setState(() => _testMode = val),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isDetecting ? null : _runDetection,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
        ),
        child: _isDetecting
            ? const CupertinoActivityIndicator(color: Colors.white)
            : const Text(
                'Initiate Detection Pipeline',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildResultsSection() {
    final bool detected = _detectionResult!['detected'] ?? false;
    final String action = _detectionResult!['action'] ?? 'UNKNOWN';
    final double confidence = _detectionResult!['confidence'] ?? 0.0;

    // Extract Antigravity Data
    final Map<String, dynamic> allocation =
        _detectionResult!['allocation_plan'] ?? {};
    final Map<String, dynamic> simulation =
        _detectionResult!['simulation'] ?? {};
    final List<dynamic> notifications =
        _detectionResult!['notifications'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary YOLO Status Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: detected
                ? AppColors.primary.withOpacity(0.05)
                : AppColors.success.withOpacity(0.05),
            border: Border.all(
              color: detected
                  ? AppColors.primary.withOpacity(0.3)
                  : AppColors.success.withOpacity(0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    detected
                        ? Icons.warning_rounded
                        : Icons.check_circle_rounded,
                    color: detected ? AppColors.primary : AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    detected ? 'CRISIS DETECTED' : 'AREA CLEAR',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: detected ? AppColors.primary : AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Recommended Action: $action',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'System Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Deep Insights (Antigravity Expandable Card)
        if (detected)
          Card(
            elevation: 0,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: const Text(
                  'Antigravity Orchestration',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                    fontSize: 15,
                  ),
                ),
                subtitle: const Text(
                  'Allocations, Simulations & Comms',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                iconColor: AppColors.info,
                collapsedIconColor: AppColors.textSecondary,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                childrenPadding: const EdgeInsets.only(
                  left: 20,
                  right: 20,
                  bottom: 20,
                ),
                children: [
                  // 1. Allocation
                  _buildInsightRow(
                    Icons.local_shipping_rounded,
                    'Resource Allocation',
                    allocation.isEmpty
                        ? 'No specific resources assigned.'
                        : allocation.entries
                              .map(
                                (e) =>
                                    '${e.value}x ${e.key.replaceAll('_', ' ')}',
                              )
                              .join('\n'),
                  ),
                  const SizedBox(height: 16),

                  // 2. Simulation
                  _buildInsightRow(
                    Icons.analytics_rounded,
                    'Simulation Impact',
                    'ETA Reduction: ${simulation['eta_reduction_minutes'] ?? 0} mins\nReroute Traffic: ${simulation['traffic_reroute'] == true ? 'Yes' : 'No'}\nSide Effects: ${simulation['side_effects'] ?? 'None predicted'}',
                  ),
                  const SizedBox(height: 16),

                  // 3. Notifications
                  _buildInsightRow(
                    Icons.cell_tower_rounded,
                    'Stakeholder Comms',
                    notifications.isEmpty
                        ? 'No alerts dispatched.'
                        : notifications
                              .map(
                                (n) =>
                                    '[${n['target'].toString().toUpperCase()}] ${n['message']}',
                              )
                              .join('\n\n'),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),

        // False Alarm Button (Only in Test Mode)
        if (_testMode && detected)
          OutlinedButton.icon(
            onPressed: _simulateFalseAlarm,
            icon: const Icon(Icons.block, color: AppColors.textMain, size: 20),
            label: const Text(
              'Simulate False Alarm',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: AppColors.textMain.withOpacity(0.2)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: AppColors.background,
            ),
          ),
      ],
    );
  }

  Widget _buildInsightRow(IconData icon, String title, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.info),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

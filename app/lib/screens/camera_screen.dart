import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../config/api_config.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
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

  // --- NEW: Antigravity Context State ---
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(
    text: "G-10, Islamabad",
  );
  bool _testMode = false;

  // Severity state from last detection
  String? _severity; // 'low' | 'medium' | 'high' | 'none' | null
  String? _recommendation; // 'monitor' | 'prepare' | 'evacuate' | 'none'
  bool _detected = false;
  double _confidence = 0.0;
  String _agentReasoning = '';

  // --- NEW: Antigravity Results State ---
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
      _resetResults();
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
        _resetResults();
      });
    });
  }

  void _resetResults() {
    _result = '';
    _severity = null;
    _recommendation = null;
    _detected = false;
    _confidence = 0.0;
    _allocationPlan = null;
    _currentCrisisId = null;
  }

  Future<void> _detectFire() async {
    if (_selectedImageBytes == null) return;
    setState(() => _loading = true);

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

      setState(() {
        _detected = result['detected'] == true;
        _confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
        _severity = (result['severity'] as String?) ?? 'none';
        _recommendation =
            (result['action'] ?? result['recommendation'] as String?) ?? 'none';
        _result = _detected
            ? '🔥 FIRE DETECTED! ${(_confidence * 100).toStringAsFixed(1)}%'
            : '✅ No fire detected';

        if (result['agent_trace'] != null) {
          _agentReasoning = json.encode(result['agent_trace']);
        }

        // --- NEW: Parse Antigravity Results ---
        _currentCrisisId = result['crisis_id'];
        _allocationPlan = result['allocation_plan'];
        _simulation = result['simulation'];

        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            content: Text('🛑 False alarm recorded and resources retracted.'),
            backgroundColor: Colors.red,
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

  // --- NEW: Context Controls Form ---
  Widget _buildContextControls() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
          const Text(
            'Multi-Signal Context',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _socialController,
            decoration: InputDecoration(
              hintText: 'Social Text (e.g., "Huge fire spreading!")',
              filled: true,
              fillColor: Colors.grey.shade100,
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
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Test Mode (Simulate False Positives)',
              style: TextStyle(fontSize: 14),
            ),
            contentPadding: EdgeInsets.zero,
            value: _testMode,
            activeColor: Colors.red,
            onChanged: (val) => setState(() => _testMode = val),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    if (!_detected) {
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
      default:
        badgeColor = Colors.amber;
        panelBorder = Colors.amber;
        alertMsg = '🟡 ALERT – Low-level fire/smoke trace detected.';
        action = 'MONITOR CLOSELY';
        actionIcon = Icons.visibility;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panelBorder.withOpacity(0.12),
            border: Border.all(color: panelBorder, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Fire Detected',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
              Text(alertMsg, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
        ),

        // --- NEW: Antigravity Expansion Tile ---
        if (_allocationPlan != null)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(top: 16),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text(
                'Antigravity Orchestration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                if (_allocationPlan!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Allocated: ${_allocationPlan!.entries.map((e) => "${e.value}x ${e.key}").join(', ')}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_simulation != null &&
                    _simulation!['traffic_reroute'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Simulation: ${_simulation!['traffic_reroute']['estimated_congestion_reduction']} congestion reduction predicted.',
                    ),
                  ),
              ],
            ),
          ),

        // --- NEW: False Alarm Button (Visible in Test Mode when crisis detected) ---
        if (_testMode)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _simulateFalseAlarm,
                icon: const Icon(Icons.block, color: Colors.red),
                label: const Text(
                  'Simulate False Alarm',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
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
      appBar: AppBar(
        title: const Text('Fire Detection'),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Camera preview
            Container(
              height: 280,
              width: double.infinity,
              color: Colors.black,
              child: _cameraReady && _videoElement != null
                  ? HtmlElementView(viewType: _videoElement!.tagName)
                  : const Center(
                      child: Text(
                        'Camera loading...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
            const SizedBox(height: 12),

            // Buttons row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _captureFrame,
                    icon: const Icon(Icons.camera),
                    label: const Text('Capture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

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
            const SizedBox(height: 16),

            // --- NEW: Render Context Controls ---
            _buildContextControls(),

            // Detect button
            ElevatedButton(
              onPressed: _detectFire,
              child: const Text('DETECT FIRE', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.red,
              ),
            ),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),

            if (_result.isNotEmpty) const SizedBox(height: 16),
            if (_result.isNotEmpty) _buildResultPanel(),

            // Confidence indicator
            if (_result.isNotEmpty)
              Column(
                children: [
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Confidence: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('${(_confidence * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _confidence,
                    backgroundColor: Colors.grey[300],
                    color: _confidence > 0.7
                        ? Colors.red
                        : (_confidence > 0.4 ? Colors.orange : Colors.green),
                    minHeight: 10,
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _confidence),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, child) => Text(
                      '${(value * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_severity != null && _severity != 'none')
                    ...([
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _severity == 'high'
                              ? Colors.red
                              : (_severity == 'medium'
                                    ? Colors.orange
                                    : Colors.yellow),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _severity?.toUpperCase() ?? 'UNKNOWN',
                          style: const TextStyle(
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

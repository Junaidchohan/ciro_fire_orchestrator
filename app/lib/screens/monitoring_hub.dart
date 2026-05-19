import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'history_screen.dart';

class MonitoringHub extends StatefulWidget {
  const MonitoringHub({super.key});

  @override
  State<MonitoringHub> createState() => _MonitoringHubState();
}

class _MonitoringHubState extends State<MonitoringHub>
    with SingleTickerProviderStateMixin {
  // ── detection state ─────────────────────────────────────────────────────────
  bool _loading = false;
  Uint8List? _selectedImageBytes;
  String _result = '';
  double _confidence = 0.0;
  String? _severity;
  String? _action;
  String? _recommendation;
  File? _selectedImage;

  // ── simulation state ────────────────────────────────────────────────────────
  bool _simLoading = false;
  Map<String, dynamic>? _simResult;
  // mock: selected crisis type for demo
  String _selectedCrisis = 'fire';
  // mock: default resource allocation for demo
  final Map<String, int> _mockResources = {
    'fire_trucks': 3,
    'ambulances': 2,
    'police_units': 4,
    'water_tankers': 2,
  };

  late final AnimationController _simAnimCtrl;
  late final Animation<double> _simFadeAnim;

  @override
  void initState() {
    super.initState();
    _simAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _simFadeAnim = CurvedAnimation(
      parent: _simAnimCtrl,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _simAnimCtrl.dispose();
    super.dispose();
  }

  // ── image pick / detect ─────────────────────────────────────────────────────
  void _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _result = '';
        _confidence = 0.0;
        _severity = null;
        _selectedImage = File(picked.path);
      });
      _detectFire();
    }
  }

  Future<void> _detectFire() async {
    if (_selectedImageBytes == null) return;
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

      setState(() {
        bool detected = result['detected'] == true;
        _confidence =
            (result['confidence'] as num?)?.toDouble() ?? 0.0;
        _severity = (result['severity'] as String?) ?? 'none';
        _action = result['action'] as String?;
        _recommendation = result['recommendation'] as String?;
        _result =
            detected ? '🔥 FIRE DETECTED!' : '✅ No fire detected';
        _loading = false;
        _showResultDialog();
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (context) {
        Color severityColor = Colors.grey;
        if (_severity != null) {
          switch (_severity!.toLowerCase()) {
            case 'high':
              severityColor = Colors.redAccent;
              break;
            case 'medium':
              severityColor = Colors.orangeAccent;
              break;
            case 'low':
              severityColor = Colors.yellowAccent;
              break;
          }
        }

        Color actionColor = Colors.cyanAccent;
        if (_action != null) {
          switch (_action!.toUpperCase()) {
            case 'EVACUATE':
              actionColor = Colors.red;
              break;
            case 'WARNING':
            case 'WARN':
              actionColor = Colors.orange;
              break;
            case 'MONITOR':
              actionColor = Colors.green;
              break;
          }
        }

        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Detection Result',
              style: GoogleFonts.outfit(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedImageBytes != null)
                Image.memory(_selectedImageBytes!,
                    height: 150, fit: BoxFit.cover),
              const SizedBox(height: 16),
              Text(
                _result,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _result.contains('FIRE')
                      ? Colors.redAccent
                      : Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                style:
                    GoogleFonts.outfit(color: AppColors.textPrimary),
              ),
              if (_severity != null && _severity != 'none') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: severityColor.withOpacity(0.4), width: 1.2),
                  ),
                  child: Text(
                    'SEVERITY: ${_severity!.toUpperCase()}',
                    style: GoogleFonts.outfit(
                      color: severityColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Recommended Action: ${_action ?? "NONE"}',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: actionColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (_recommendation != null && _recommendation!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _recommendation!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: AppColors.textPrimary.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close',
                  style: GoogleFonts.outfit(color: AppColors.primary)),
            )
          ],
        );
      },
    );
  }

  void _pickVideo() {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video upload coming soon!')));
  }

  // ── simulation ──────────────────────────────────────────────────────────────
  Future<void> _runSimulation() async {
    setState(() {
      _simLoading = true;
      _simResult = null;
    });
    _simAnimCtrl.reset();

    try {
      final body = json.encode({
        'crisis_type': _selectedCrisis,
        'allocated_resources': _mockResources,
        'location': 'Downtown District',
      });
      final response = await http.post(
        Uri.parse(ApiConfig.simulate),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (response.statusCode == 200) {
        setState(() {
          _simResult =
              json.decode(response.body) as Map<String, dynamic>;
          _simLoading = false;
        });
        _simAnimCtrl.forward();
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _simLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Simulation error: $e')));
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  Widget _buildCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surfaceElevated,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withOpacity(0.5), width: 1.5),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.2), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a single state column (before or after) for the comparison panel.
  Widget _buildStateColumn({
    required String label,
    required Map<String, dynamic> state,
    required Color accentColor,
    required IconData headerIcon,
  }) {
    final rows = <Map<String, dynamic>>[
      {
        'key': 'Affected Population',
        'val': state['affected_population']?.toString() ?? '—',
        'icon': Icons.people_alt_rounded,
      },
      {
        'key': 'Traffic Congestion',
        'val': (state['traffic_congestion'] as String? ?? '—').toUpperCase(),
        'icon': Icons.traffic_rounded,
      },
      {
        'key': 'Emergency Response',
        'val': (state['emergency_response'] as String? ?? '—')
            .replaceAll('_', ' ')
            .toUpperCase(),
        'icon': Icons.local_hospital_rounded,
      },
      {
        'key': 'Est. Damage',
        'val': (state['estimated_damage'] as String? ?? '—').toUpperCase(),
        'icon': Icons.bar_chart_rounded,
      },
      if (state.containsKey('improvement'))
        {
          'key': 'Improvement',
          'val': state['improvement'],
          'icon': Icons.trending_down_rounded,
        },
    ];

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withOpacity(0.4), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Column header
            Row(
              children: [
                Icon(headerIcon, color: accentColor, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Metric rows
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(r['icon'] as IconData,
                        size: 16,
                        color: AppColors.textPrimary.withOpacity(0.55)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['key'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color:
                                  AppColors.textPrimary.withOpacity(0.55),
                            ),
                          ),
                          Text(
                            r['val'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the impact metric chips row.
  Widget _buildImpactChips(Map<String, dynamic> metrics) {
    final chips = <Map<String, dynamic>>[
      {
        'label':
            '${metrics['response_time_improvement_pct']}% faster response',
        'icon': Icons.speed_rounded,
        'color': Colors.greenAccent,
      },
      {
        'label':
            '${metrics['population_protected']} people protected',
        'icon': Icons.shield_rounded,
        'color': Colors.blueAccent,
      },
      {
        'label':
            '${metrics['total_resources_deployed']} resources deployed',
        'icon': Icons.local_fire_department_rounded,
        'color': Colors.orangeAccent,
      },
      if (metrics['congestion_reduced'] == true)
        {
          'label': 'Congestion reduced',
          'icon': Icons.directions_car_rounded,
          'color': Colors.purpleAccent,
        },
      if (metrics['damage_downgraded'] == true)
        {
          'label': 'Damage downgraded',
          'icon': Icons.trending_down_rounded,
          'color': Colors.tealAccent,
        },
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: chips.map((c) {
        final color = c['color'] as Color;
        return Chip(
          avatar: Icon(c['icon'] as IconData, size: 14, color: color),
          label: Text(
            c['label'] as String,
            style: GoogleFonts.outfit(fontSize: 11, color: color),
          ),
          backgroundColor: color.withOpacity(0.12),
          side: BorderSide(color: color.withOpacity(0.4), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }

  /// Simulation panel widget embedded in the ListView.
  Widget _buildSimulationPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: Colors.cyanAccent.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.15),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded,
                    color: Colors.cyanAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Action Simulation',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Crisis type selector
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCrisis,
                    dropdownColor: AppColors.surfaceElevated,
                    style: GoogleFonts.outfit(
                        color: Colors.cyanAccent, fontSize: 13),
                    icon: const Icon(Icons.expand_more,
                        color: Colors.cyanAccent, size: 18),
                    items: ['fire', 'flood', 'heatwave'].map((c) {
                      return DropdownMenuItem(
                          value: c,
                          child: Text(c[0].toUpperCase() + c.substring(1)));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCrisis = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Run simulation button
                ElevatedButton.icon(
                  onPressed: _simLoading ? null : _runSimulation,
                  icon: _simLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.bolt_rounded,
                          size: 16, color: Colors.black),
                  label: Text(
                    _simLoading ? 'Simulating…' : 'Run',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          // Simulation results (animated)
          if (_simResult != null)
            FadeTransition(
              opacity: _simFadeAnim,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── before / after columns ───────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStateColumn(
                          label: 'BEFORE',
                          state:
                              _simResult!['before'] as Map<String, dynamic>,
                          accentColor: Colors.redAccent,
                          headerIcon: Icons.warning_amber_rounded,
                        ),
                        // Arrow divider
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.cyanAccent.withOpacity(0.7),
                            size: 26,
                          ),
                        ),
                        _buildStateColumn(
                          label: 'AFTER',
                          state:
                              _simResult!['after'] as Map<String, dynamic>,
                          accentColor: Colors.greenAccent,
                          headerIcon: Icons.check_circle_rounded,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── simulation time badge ────────────────────────────────
                    Row(
                      children: [
                        const Icon(Icons.timer_rounded,
                            size: 14,
                            color: Colors.cyanAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Simulated in ${_simResult!['simulation_time_seconds']}s',
                          style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.textPrimary.withOpacity(0.6)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Divider(color: Colors.white.withOpacity(0.08)),
                    const SizedBox(height: 10),

                    // ── impact metrics ───────────────────────────────────────
                    Text(
                      'Impact Metrics',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildImpactChips(
                        _simResult!['impact_metrics']
                            as Map<String, dynamic>),
                  ],
                ),
              ),
            )
          else if (!_simLoading)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text(
                'Select a crisis type and press Run to see before/after impact.',
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppColors.textPrimary.withOpacity(0.5)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Monitoring Center',
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        flexibleSpace: Container(
          decoration:
              const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── monitoring cards grid ────────────────────────────────────
              if (_selectedImage != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(_selectedImage!, height: 200, fit: BoxFit.cover),
                ),
                const SizedBox(height: 16),
              ],
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildCard(
                    icon: Icons.videocam,
                    title: 'Start Live Monitoring',
                    color: Colors.redAccent,
                    onTap: () =>
                        Navigator.pushNamed(context, '/camera'),
                  ),
                  _buildCard(
                    icon: Icons.image,
                    title: 'Upload Image',
                    color: Colors.blueAccent,
                    onTap: _pickImage,
                  ),
                  _buildCard(
                    icon: Icons.video_library,
                    title: 'Upload Video',
                    color: Colors.purpleAccent,
                    onTap: _pickVideo,
                  ),
                  _buildCard(
                    icon: Icons.history,
                    title: 'View Detection Logs',
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  _buildCard(
                    icon: Icons.psychology,
                    title: 'Agent Reasoning Trace',
                    color: Colors.greenAccent,
                    onTap: () =>
                        Navigator.pushNamed(context, '/traces'),
                  ),
                  _buildCard(
                    icon: Icons.warning_amber_rounded,
                    title: 'Incident History',
                    color: Colors.amberAccent,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── section label ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Crisis Action Simulation',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              // ── simulation panel ─────────────────────────────────────────
              _buildSimulationPanel(),
            ],
          ),

          // Loading overlay (for detect)
          if (_loading)
            Container(
              color: Colors.black54,
              child: const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

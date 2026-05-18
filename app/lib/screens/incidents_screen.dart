import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../config/api_config.dart';

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.history),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _records = data.cast<Map<String, dynamic>>();
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Server returned ${response.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect to backend: $e';
          _loading = false;
        });
      }
    }
  }

  String _formatTimestamp(String? ts) {
    if (ts == null || ts.isEmpty) return 'Unknown time';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final date = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
      final time = '${_pad(dt.hour)}:${_pad(dt.minute)}';
      return '$date at $time';
    } catch (_) {
      return ts;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.secondary;
      case 'low':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  void _showIncidentDetail(BuildContext context, Map<String, dynamic> record) {
    final imageName = record['image_name'] as String? ?? '';
    final imageUrl = '${ApiConfig.baseUrl}/images/$imageName';
    final detected = record['detected'] as bool? ?? false;
    final confidence = ((record['confidence'] as num? ?? 0.0) * 100).toStringAsFixed(1);
    final ts = _formatTimestamp(record['timestamp'] as String?);
    final severity = record['severity'] as String? ?? 'None';
    final crisisType = (record['crisis_type'] as String?)?.toUpperCase() ?? (detected ? 'FIRE' : 'NONE');

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Incident Detail',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
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
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: imageName.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                const SizedBox(height: 16),
                _detailRow('Crisis Type', detected ? crisisType : 'Clear'),
                _detailRow('Severity', severity.toUpperCase()),
                _detailRow('Confidence', '$confidence%'),
                _detailRow('Timestamp', ts),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 200,
      width: double.infinity,
      color: AppColors.background,
      child: Center(
        child: Icon(Icons.image_not_supported, color: AppColors.textMuted, size: 40),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          Text(
            value,
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> record) {
    final detected = record['detected'] as bool? ?? false;
    final severity = record['severity'] as String? ?? 'none';
    final ts = _formatTimestamp(record['timestamp'] as String?);
    final confidence = ((record['confidence'] as num? ?? 0.0) * 100).toStringAsFixed(1);
    final crisisType = (record['crisis_type'] as String?)?.toUpperCase() ?? (detected ? 'FIRE' : 'NONE');

    final color = detected ? _severityColor(severity) : AppColors.success;
    final icon = detected ? Icons.warning_rounded : Icons.check_circle_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      child: InkWell(
        onTap: () => _showIncidentDetail(context, record),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detected ? '$crisisType INCIDENT' : 'AREA CLEAR',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ts,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (detected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color, width: 1),
                      ),
                      child: Text(
                        severity.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '$confidence%',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.outfit(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchHistory,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        child: Text('Retry', style: GoogleFonts.outfit(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : _records.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 64, color: AppColors.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'No incidents detected',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchHistory,
                      color: AppColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (context, index) => _buildIncidentCard(_records[index]),
                      ),
                    ),
    );
  }
}

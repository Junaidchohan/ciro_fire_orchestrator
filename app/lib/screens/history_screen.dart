import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../config/api_config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
      final response = await http.get(Uri.parse(ApiConfig.history));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _records = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error =
              'Server returned ${response.statusCode}\n(Make sure /history exists in your backend!)';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error =
            'Could not connect to backend.\nEnsure your server is running.';
        _loading = false;
      });
    }
  }

  String _formatTimestamp(String? ts) {
    if (ts == null || ts.isEmpty) return 'Unknown time';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final date = '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
      final time = '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
      return '$date  $time';
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
        return AppColors.warning;
      case 'low':
        return AppColors.secondary ?? Colors.amber;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _severityChip(String severity) {
    final color = _severityColor(severity);
    final label = severity.isEmpty ? 'N/A' : severity.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  void _showImageDetail(BuildContext context, Map<String, dynamic> record) {
    final imageName = record['image_name'] as String? ?? '';
    final imageUrl = '${ApiConfig.baseUrl}/images/$imageName';
    final detected = record['detected'] as bool? ?? false;
    final confidence = ((record['confidence'] as num? ?? 0.0) * 100)
        .toStringAsFixed(1);
    final ts = _formatTimestamp(record['timestamp'] as String?);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _statusBadge(detected),
                  const SizedBox(width: 8),
                  _severityChip(record['severity'] as String? ?? ''),
                  const Spacer(),
                  Text(
                    ts,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$confidence% System Confidence',
                style: GoogleFonts.outfit(
                  color: AppColors.textMain,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageName.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  imageName.isNotEmpty
                      ? 'Source File: $imageName'
                      : 'No image name available',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            'Image not available on server',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool detected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (detected ? AppColors.error : AppColors.success).withOpacity(
          0.1,
        ),
        border: Border.all(
          color: detected ? AppColors.error : AppColors.success,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected ? Icons.local_fire_department : Icons.check_circle,
            color: detected ? AppColors.error : AppColors.success,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            detected ? 'FIRE DETECTED' : 'NO FIRE',
            style: GoogleFonts.outfit(
              color: detected ? AppColors.error : AppColors.success,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> record) {
    final detected = record['detected'] as bool? ?? false;
    final confidence = ((record['confidence'] as num? ?? 0.0) * 100)
        .toStringAsFixed(1);
    final ts = _formatTimestamp(record['timestamp'] as String?);
    final imageName = record['image_name'] as String? ?? 'unknown';

    return GestureDetector(
      onTap: () => _showImageDetail(context, record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: detected
                ? AppColors.error.withOpacity(0.3)
                : Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: detected
                    ? AppColors.error.withOpacity(0.1)
                    : AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                detected ? Icons.local_fire_department : Icons.check_circle,
                color: detected ? AppColors.error : AppColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ts,
                    style: GoogleFonts.outfit(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    imageName,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(detected),
                const SizedBox(height: 6),
                Text(
                  '$confidence%',
                  style: GoogleFonts.outfit(
                    color: AppColors.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countChip(int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
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
          'Detection History',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 16))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      color: AppColors.error,
                      size: 52,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _fetchHistory,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Connection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _records.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No detections logged yet.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchHistory,
              color: AppColors.primary,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_records.length} Records',
                          style: GoogleFonts.outfit(
                            color: AppColors.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        _countChip(
                          _records.where((r) => r['detected'] == true).length,
                          AppColors.error,
                          Icons.local_fire_department,
                        ),
                        const SizedBox(width: 8),
                        _countChip(
                          _records.where((r) => r['detected'] == false).length,
                          AppColors.success,
                          Icons.check_circle,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _records.length,
                      itemBuilder: (_, i) => _buildCard(_records[i]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';

/// HistoryScreen – displays all past fire detection records fetched from
/// the backend GET /history endpoint, sorted newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // List of detection records returned by the backend
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  /// Fetches detection history from the backend.
  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8000/history'),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _records = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not connect to backend: $e';
        _loading = false;
      });
    }
  }

  /// Formats an ISO-8601 timestamp string into a readable date/time label.
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

  /// Returns a color matching the severity level.
  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.yellow.shade700;
      default:
        return Colors.grey;
    }
  }

  /// Severity chip shown on each card.
  Widget _severityChip(String severity) {
    final color = _severityColor(severity);
    final label = severity.isEmpty ? 'N/A' : severity.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
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

  /// Shows a bottom sheet with enlarged view of the captured image.
  void _showImageDetail(BuildContext context, Map<String, dynamic> record) {
    final imageName = record['image_name'] as String? ?? '';
    // The backend serves saved images under /images/<filename> (mock: static file)
    final imageUrl = 'http://localhost:8000/images/$imageName';
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
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Status badge row
              Row(
                children: [
                  _statusBadge(detected),
                  const SizedBox(width: 8),
                  _severityChip(record['severity'] as String? ?? ''),
                  const SizedBox(width: 10),
                  Text(
                    '$confidence% confidence',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    ts,
                    style: GoogleFonts.outfit(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Image display
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
              Text(
                imageName.isNotEmpty ? imageName : 'No image name',
                style: GoogleFonts.outfit(
                  color: AppColors.textMuted,
                  fontSize: 12,
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
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text('Image not available',
              style:
                  GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  /// Colored chip indicating fire detected vs safe.
  Widget _statusBadge(bool detected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: detected
            ? const LinearGradient(
                colors: [Color(0xFFFF4500), Color(0xFFFF8C00)],
              )
            : const LinearGradient(
                colors: [Color(0xFF00C853), Color(0xFF1DE9B6)],
              ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            detected ? Icons.local_fire_department : Icons.check_circle,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            detected ? 'FIRE DETECTED' : 'NO FIRE',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single detection record card.
  Widget _buildCard(Map<String, dynamic> record) {
    final detected = record['detected'] as bool? ?? false;
    final confidence =
        ((record['confidence'] as num? ?? 0.0) * 100).toStringAsFixed(1);
    final ts = _formatTimestamp(record['timestamp'] as String?);
    final imageName = record['image_name'] as String? ?? 'unknown';

    return GestureDetector(
      onTap: () => _showImageDetail(context, record),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: detected
              ? LinearGradient(
                  colors: [
                    const Color(0xFFFF4500).withOpacity(0.12),
                    AppColors.surface,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : LinearGradient(
                  colors: [
                    const Color(0xFF00C853).withOpacity(0.10),
                    AppColors.surface,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: detected
                ? const Color(0xFFFF4500).withOpacity(0.35)
                : const Color(0xFF00C853).withOpacity(0.30),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left: fire icon circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: detected
                    ? const Color(0xFFFF4500).withOpacity(0.18)
                    : const Color(0xFF00C853).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                detected ? Icons.local_fire_department : Icons.check_circle,
                color: detected ? const Color(0xFFFF6525) : const Color(0xFF00C853),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),

            // Center: timestamp + image name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ts,
                    style: GoogleFonts.outfit(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    imageName,
                    style: GoogleFonts.outfit(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Right: confidence badge + severity + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusBadge(detected),
                const SizedBox(height: 4),
                _severityChip(record['severity'] as String? ?? ''),
                const SizedBox(height: 4),
                Text(
                  '$confidence%',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
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
            color: AppColors.textPrimary,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            tooltip: 'Refresh',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 52),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: GoogleFonts.outfit(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _fetchHistory,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
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
                          Icon(Icons.history,
                              size: 64,
                              color: AppColors.textMuted.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            'No detections yet',
                            style: GoogleFonts.outfit(
                              color: AppColors.textMuted,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Run a detection on the Camera screen\nto see history here.',
                            style: GoogleFonts.outfit(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Summary header bar
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.surfaceElevated, width: 1),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.history,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '${_records.length} detection${_records.length == 1 ? '' : 's'} recorded',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              // Fire count chip
                              _countChip(
                                _records.where((r) => r['detected'] == true).length,
                                const Color(0xFFFF4500),
                                Icons.local_fire_department,
                              ),
                              const SizedBox(width: 6),
                              // Safe count chip
                              _countChip(
                                _records.where((r) => r['detected'] == false).length,
                                const Color(0xFF00C853),
                                Icons.check_circle,
                              ),
                            ],
                          ),
                        ),
                        // List
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 20),
                            itemCount: _records.length,
                            itemBuilder: (_, i) => _buildCard(_records[i]),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _countChip(int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

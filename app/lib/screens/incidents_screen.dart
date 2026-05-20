import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

class ApiConfig {
  static const String baseUrl =
      'http://localhost:8000'; // Change to 10.0.2.2 if on Android Emulator
  static const String crises = '$baseUrl/crises';
}

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({Key? key}) : super(key: key);

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  List<dynamic> _activeCrises = [];
  Map<String, dynamic> _availableUnits = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCrises();
  }

  Future<void> _fetchCrises() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(ApiConfig.crises));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _activeCrises = data['active_crises'] ?? [];
          _availableUnits = data['available_units'] ?? {};
          _isLoading = false;
        });
      } else {
        _showError('Failed to load active incidents.');
      }
    } catch (e) {
      _showError('Connection error: $e');
    }
  }

  Future<void> _resolveCrisis(String id) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/resolve_crisis/$id'),
      );
      if (response.statusCode == 200) {
        _fetchCrises(); // Refresh the list
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Crisis resolved. Resources returned to pool.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to resolve crisis: $e');
    }
  }

  void _showError(String msg) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return 'Unknown Time';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM dd, HH:mm').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(radius: 16))
          : RefreshIndicator(
              onRefresh: _fetchCrises,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildResourceDashboard(),
                  const SizedBox(height: 24),
                  const Text(
                    'Active Incidents',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_activeCrises.isEmpty)
                    _buildEmptyState()
                  else
                    ..._activeCrises.reversed
                        .map((crisis) => _buildCrisisCard(crisis))
                        .toList(),
                ],
              ),
            ),
    );
  }

  Widget _buildResourceDashboard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Global Fleet Status',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _availableUnits.entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${e.value} ${e.key.replaceAll('_', ' ').toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCrisisCard(Map<String, dynamic> crisis) {
    final String id = crisis['id'] ?? '';
    final String type = crisis['type'] ?? 'UNKNOWN';
    final String location = crisis['location'] ?? 'Unknown Location';
    final String status = crisis['status'] ?? 'active';
    final double severity = crisis['severity'] ?? 0.0;
    final Map<String, dynamic> alloc = crisis['allocated_resources'] ?? {};

    final bool needsVerification = status == 'verification_required';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: needsVerification
              ? AppColors.warning.withOpacity(0.5)
              : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (needsVerification
                                ? AppColors.warning
                                : AppColors.primary)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    needsVerification
                        ? 'NEEDS VERIFICATION'
                        : type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: needsVerification
                          ? AppColors.warning
                          : AppColors.primary,
                    ),
                  ),
                ),
                Text(
                  _formatTime(crisis['timestamp']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              location,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Severity: ${(severity * 100).toStringAsFixed(0)}%  |  ID: ${id.substring(0, 8)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),

            if (alloc.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Divider(height: 1),
              ),
              const Text(
                'Dispatched Units:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: alloc.entries
                    .map(
                      (e) => Chip(
                        label: Text(
                          '${e.value}x ${e.key.replaceAll('_', ' ')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: AppColors.background,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _resolveCrisis(id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: needsVerification
                      ? AppColors.warning
                      : AppColors.success,
                  side: BorderSide(
                    color:
                        (needsVerification
                                ? AppColors.warning
                                : AppColors.success)
                            .withOpacity(0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  needsVerification ? 'Reject / Retract' : 'Mark as Resolved',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Column(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              'No active incidents.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

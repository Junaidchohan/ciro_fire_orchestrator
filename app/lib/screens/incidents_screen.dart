import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/event_bus.dart';
import '../config/api_config.dart';

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  List<dynamic> _activeCrises = [];
  Map<String, dynamic> _availableUnits = {};
  bool _isLoading = true;
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _fetchCrises();
    _eventSub = EventBus().stream.listen((event) {
      if (mounted) _fetchCrises();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchCrises();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchCrises() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/crises'));
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
        _fetchCrises();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Crisis resolved. Resources returned to pool.',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to resolve crisis: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        backgroundColor: AppColors.primary,
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF9F9FB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Incidents',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: _isLoading && _activeCrises.isEmpty
          ? const Center(child: CupertinoActivityIndicator(radius: 16))
          : RefreshIndicator(
              onRefresh: _fetchCrises,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
                  _buildResourceDashboard(isDark),
                  const SizedBox(height: 32),
                  Text(
                    'Active Incidents',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_activeCrises.isEmpty)
                    _buildEmptyState(isDark)
                  else
                    ..._activeCrises.reversed
                        .map((crisis) => _buildCrisisCard(crisis, isDark))
                        .toList(),
                ],
              ),
            ),
    );
  }

  Widget _buildResourceDashboard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                'Global Fleet Status',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _availableUnits.entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  '${e.value} ${e.key.replaceAll('_', ' ').toUpperCase()}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCrisisCard(Map<String, dynamic> crisis, bool isDark) {
    final String id = crisis['id'] ?? '';
    final String type = crisis['type'] ?? 'UNKNOWN';
    final String location = crisis['location'] ?? 'Unknown Location';
    final String status = crisis['status'] ?? 'active';
    final double severity = crisis['severity'] ?? 0.0;
    
    final bool needsVerification = status == 'verification_required';
    final bool isFire = type.toLowerCase() == 'fire';
    
    final Color typeColor = isFire ? AppColors.error : AppColors.warning;
    final IconData typeIcon = isFire ? Icons.local_fire_department : Icons.cloud;

    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: typeColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(crisis['timestamp']),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: subtitleColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(severity * 100).toStringAsFixed(0)}% SEV',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: subtitleColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    location,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolveCrisis(id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: needsVerification ? AppColors.warning : AppColors.success,
                      side: BorderSide(
                        color: (needsVerification ? AppColors.warning : AppColors.success).withOpacity(0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      needsVerification ? 'Retract' : 'Resolve',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showDetailsBottomSheet(context, id, isDark),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'View Details',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailsBottomSheet(BuildContext context, String crisisId, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Agent Traces',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<http.Response>(
                  future: http.get(Uri.parse('${ApiConfig.baseUrl}/traces')),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CupertinoActivityIndicator(radius: 16));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error loading traces', style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black87)));
                    }

                    try {
                      final data = jsonDecode(snapshot.data!.body) as List;
                      final crisisTraces = data.where((t) => t['crisis_id'] == crisisId).toList();
                      
                      if (crisisTraces.isEmpty) {
                        return Center(child: Text('No traces found for this incident.', style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black87)));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: crisisTraces.length,
                        itemBuilder: (context, index) {
                          final trace = crisisTraces[index];
                          return Card(
                            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        trace['agent_name'] ?? 'Agent',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          trace['step_type'] ?? 'Step',
                                          style: GoogleFonts.outfit(fontSize: 10, color: Colors.white),
                                        ),
                                        backgroundColor: AppColors.primary,
                                        padding: EdgeInsets.zero,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    trace['reasoning'] ?? '',
                                    style: GoogleFonts.outfit(
                                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatTime(trace['timestamp']),
                                    style: GoogleFonts.outfit(
                                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    } catch (e) {
                      return Center(child: Text('Error parsing traces', style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black87)));
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'All Clear',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No active incidents at the moment.',
              style: GoogleFonts.outfit(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

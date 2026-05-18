import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';
import '../config/api_config.dart';

class TraceLog {
  final String agentName;
  final String stepType;
  final String reasoning;
  final double confidenceBefore;
  final double confidenceAfter;
  final String timestamp;

  TraceLog({
    required this.agentName,
    required this.stepType,
    required this.reasoning,
    required this.confidenceBefore,
    required this.confidenceAfter,
    required this.timestamp,
  });

  factory TraceLog.fromJson(Map<String, dynamic> json) {
    return TraceLog(
      agentName: json['agent_name'] ?? 'Unknown',
      stepType: json['step_type']?.toString().toUpperCase() ?? 'UNKNOWN',
      reasoning: json['reasoning'] ?? '',
      confidenceBefore: (json['confidence_before'] ?? 0.0).toDouble(),
      confidenceAfter: (json['confidence_after'] ?? 0.0).toDouble(),
      timestamp: json['timestamp'] ?? '',
    );
  }
}

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  List<TraceLog> _allTraces = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'OBSERVE',
    'ANALYZE',
    'DECIDE',
    'ACT',
    'EVALUATE',
  ];

  @override
  void initState() {
    super.initState();
    _fetchTraces();
  }

  Future<void> _fetchTraces() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(Uri.parse(ApiConfig.traces));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _allTraces = data.map((json) => TraceLog.fromJson(json)).toList();
            _allTraces.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<TraceLog> get _filteredTraces {
    if (_selectedFilter == 'All') return _allTraces;
    return _allTraces.where((t) => t.stepType.contains(_selectedFilter)).toList();
  }

  Color _getStepColor(String stepType) {
    switch (stepType) {
      case 'OBSERVE': return AppColors.info;
      case 'ANALYZE': return AppColors.tertiary;
      case 'DECIDE': return AppColors.warning;
      case 'ACT': return AppColors.success;
      case 'EVALUATE': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }

  IconData _getStepIcon(String stepType) {
    switch (stepType) {
      case 'OBSERVE': return Icons.visibility_outlined;
      case 'ANALYZE': return Icons.analytics_outlined;
      case 'DECIDE': return Icons.psychology_outlined;
      case 'ACT': return Icons.bolt_outlined;
      case 'EVALUATE': return Icons.fact_check_outlined;
      default: return Icons.memory;
    }
  }

  String _formatTimestamp(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Filter Chips Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: AppColors.surface,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        filter,
                        style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _selectedFilter = filter);
                      },
                      backgroundColor: AppColors.surfaceElevated,
                      selectedColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // Traces List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    onRefresh: _fetchTraces,
                    color: AppColors.primary,
                    child: _filteredTraces.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _filteredTraces.length,
                            itemBuilder: (context, index) {
                              return _buildTraceCard(_filteredTraces[index]);
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraceCard(TraceLog trace) {
    final color = _getStepColor(trace.stepType);
    final icon = _getStepIcon(trace.stepType);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trace.agentName,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        _formatTimestamp(trace.timestamp),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(
                    trace.stepType,
                    style: GoogleFonts.outfit(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              trace.reasoning.length > 80 
                  ? '${trace.reasoning.substring(0, 80)}...' 
                  : trace.reasoning,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildConfidenceBadge('Before', trace.confidenceBefore),
                Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.textMuted),
                _buildConfidenceBadge('After', trace.confidenceAfter),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(String label, double value) {
    final valPercent = (value * 100).toStringAsFixed(0);
    return Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.outfit(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        Text(
          '$valPercent%',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.memory,
            size: 64,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No agent traces yet',
            style: GoogleFonts.outfit(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Traces will appear here once an\nincident is processed.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

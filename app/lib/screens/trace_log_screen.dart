import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_colors.dart';

// mock: trace model mapped from Firestore/FastAPI JSON trace
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

class TraceLogScreen extends StatefulWidget {
  const TraceLogScreen({super.key});

  @override
  State<TraceLogScreen> createState() => _TraceLogScreenState();
}

class _TraceLogScreenState extends State<TraceLogScreen> {
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
      // NOTE: Using localhost. In Android emulator use 10.0.2.2:8001
      final response = await http.get(Uri.parse('http://127.0.0.1:8001/traces'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _allTraces = data.map((json) => TraceLog.fromJson(json)).toList();
          // Sort newest first
          _allTraces.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<TraceLog> get _filteredTraces {
    if (_selectedFilter == 'All') {
      return _allTraces;
    }
    return _allTraces.where((t) => t.stepType.contains(_selectedFilter)).toList();
  }

  Color _getStepColor(String stepType) {
    switch (stepType) {
      case 'OBSERVE':
        return AppColors.info;
      case 'ANALYZE':
        return AppColors.tertiary;
      case 'DECIDE':
        return AppColors.warning;
      case 'ACT':
        return AppColors.success;
      case 'EVALUATE':
        return AppColors.error;
      default:
        return AppColors.agentFusion; // Default bright accent
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Agent Traces',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.appBarGradient,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: _fetchTraces,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips Container
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: _filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(
                      filter,
                      style: GoogleFonts.inter(
                        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    backgroundColor: AppColors.surfaceElevated,
                    selectedColor: AppColors.primary,
                    checkmarkColor: AppColors.textPrimary,
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Traces List View
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchTraces,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceElevated,
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
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trace.agentName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStepColor(trace.stepType).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    trace.stepType,
                    style: TextStyle(
                      color: _getStepColor(trace.stepType),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              trace.reasoning.length > 100 
                  ? trace.reasoning.substring(0, 100) + '...' 
                  : trace.reasoning,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              'confidence: ${trace.confidenceBefore.toStringAsFixed(2)} → ${trace.confidenceAfter.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// Center state shown when trace list is empty
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No traces yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

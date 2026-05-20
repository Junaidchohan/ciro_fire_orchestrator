import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// --- Configuration ---
class ApiConfig {
  // Configured for Web (localhost). If moving back to Android Emulator, change to 10.0.2.2
  static const String baseUrl = 'http://localhost:8000';
  static const String traces = '$baseUrl/traces';
  static const String antigravityTraces = '$baseUrl/antigravity_traces';
}

class AppColors {
  static const Color primary = Color(0xFFD32F2F);
  static const Color background = Color(0xFFF5F5F7);
  static const Color surface = Colors.white;
  static const Color textMain = Color(0xFF1D1D1F);
  static const Color textSecondary = Color(0xFF86868B);
  static const Color accent = Color(0xFF007AFF);
  static const Color warning = Color(0xFFFF9500);
}

class AgentTracesScreen extends StatefulWidget {
  const AgentTracesScreen({Key? key}) : super(key: key);

  @override
  State<AgentTracesScreen> createState() => _AgentTracesScreenState();
}

class _AgentTracesScreenState extends State<AgentTracesScreen> {
  List<dynamic> _standardTraces = [];
  List<dynamic> _agTraces = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTraces();
  }

  Future<void> _fetchTraces() async {
    setState(() => _isLoading = true);
    try {
      // Fetch both trace types concurrently
      final responses = await Future.wait([
        http.get(Uri.parse(ApiConfig.traces)),
        http.get(Uri.parse(ApiConfig.antigravityTraces)),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        setState(() {
          _standardTraces = jsonDecode(responses[0].body);
          _agTraces = jsonDecode(responses[1].body);
          _isLoading = false;
        });
      } else {
        _showError('Failed to load traces from server.');
      }
    } catch (e) {
      _showError('Connection error: $e');
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
      return DateFormat('HH:mm:ss').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'System Traces',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchTraces),
        ],
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(radius: 16))
          : RefreshIndicator(
              onRefresh: _fetchTraces,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader(
                    'Antigravity Plans',
                    Icons.psychology_outlined,
                  ),
                  const SizedBox(height: 12),
                  if (_agTraces.isEmpty)
                    _buildEmptyState('No Antigravity plans generated yet.')
                  else
                    ..._agTraces.reversed
                        .map((trace) => _buildAgTraceCard(trace))
                        .toList(),

                  const SizedBox(height: 32),

                  _buildSectionHeader(
                    'Standard Agent Pipeline',
                    Icons.memory_outlined,
                  ),
                  const SizedBox(height: 12),
                  if (_standardTraces.isEmpty)
                    _buildEmptyState('No standard traces found.')
                  else
                    ..._standardTraces
                        .map((trace) => _buildStandardTraceCard(trace))
                        .toList(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          msg,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildAgTraceCard(Map<String, dynamic> trace) {
    final String decision = trace['final_decision'] ?? 'Unknown Decision';
    final String reasoning = trace['reasoning'] ?? '';
    final Map<String, dynamic> alloc = trace['allocation_plan'] ?? {};
    final bool isRetraction =
        trace['workplan']?.contains('retract_crisis') ?? false;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRetraction
              ? AppColors.warning.withOpacity(0.5)
              : Colors.grey.shade200,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: isRetraction
                ? AppColors.warning.withOpacity(0.1)
                : AppColors.accent.withOpacity(0.1),
            child: Icon(
              isRetraction ? Icons.block : Icons.insights,
              color: isRetraction ? AppColors.warning : AppColors.accent,
              size: 20,
            ),
          ),
          title: Text(
            isRetraction
                ? 'FALSE ALARM RETRACTION'
                : decision.toUpperCase().replaceAll('_', ' '),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textMain,
            ),
          ),
          subtitle: const Text(
            'AG Engine Reasoning Trace',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          childrenPadding: const EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: 20,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                reasoning,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textMain,
                ),
              ),
            ),
            if (!isRetraction && alloc.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Network Allocations',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: alloc.entries
                      .map(
                        (e) => Chip(
                          label: Text(
                            '${e.value}x ${e.key.replaceAll('_', ' ')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: AppColors.background,
                          side: BorderSide.none,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStandardTraceCard(Map<String, dynamic> trace) {
    final String stepType = trace['step_type'] ?? 'UNKNOWN';
    final String reasoning = trace['reasoning'] ?? 'No reasoning provided';
    final String agent = trace['agent_name'] ?? 'System';
    final String time = _formatTime(trace['timestamp']);

    // Highlight EVALUATE steps (like false alarm retractions)
    final bool isEval = stepType == 'EVALUATE';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEval
              ? AppColors.warning.withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
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
                  color: (isEval ? AppColors.warning : AppColors.textMain)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stepType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isEval ? AppColors.warning : AppColors.textMain,
                  ),
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reasoning,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMain,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Agent: ${agent.toUpperCase()}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

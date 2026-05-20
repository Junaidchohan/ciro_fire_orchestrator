import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_colors.dart';
import '../config/api_config.dart';
import '../services/event_bus.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic> _data = {};
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _eventSub = EventBus().stream.listen((event) {
      if (mounted) _refreshData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshData();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshData() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/traces'));
      if (response.statusCode == 200) {
        final rawTraces = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _computeAnalytics(rawTraces);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load analytics: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error connecting to backend: $e';
        _isLoading = false;
      });
    }
  }

  void _computeAnalytics(List<dynamic> traces) {
    int fireCount = 0;
    double fireSum = 0;
    int smokeCount = 0;
    double smokeSum = 0;
    
    final Map<String, String> crisesMap = {}; 
    
    for (var t in traces) {
      final crisisId = t['crisis_id']?.toString() ?? t['timestamp']?.toString() ?? '';
      final ts = t['timestamp']?.toString();
      final agent = t['agent_name']?.toString() ?? '';
      final conf = (t['confidence_after'] as num?)?.toDouble() ?? 0.0;
      
      if (conf > 0) {
        if (agent.toLowerCase().contains('fire')) {
           fireSum += conf;
           fireCount++;
        } else if (agent.toLowerCase().contains('smoke')) {
           smokeSum += conf;
           smokeCount++;
        }
      }
      
      if (ts != null && ts.length >= 10 && crisisId.isNotEmpty) {
          final dateStr = ts.substring(0, 10);
          crisesMap[crisisId] = dateStr;
      }
    }
    
    final Map<String, int> dailyCounts = {};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dStr = now.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
      dailyCounts[dStr] = 0;
    }
    
    for (var date in crisesMap.values) {
      if (dailyCounts.containsKey(date)) {
        dailyCounts[date] = dailyCounts[date]! + 1;
      }
    }
    
    final crisesPerDay = dailyCounts.entries.map((e) => {'date': e.key, 'count': e.value}).toList();
    crisesPerDay.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    
    _data = {
      'avg_confidence': {
        'fire': fireCount > 0 ? fireSum / fireCount : 0.0,
        'smoke': smokeCount > 0 ? smokeSum / smokeCount : 0.0,
      },
      'crises_per_day': crisesPerDay,
      'resources_per_day': crisesPerDay.map((e) => {
         'date': e['date'],
         'allocations': {
            'ambulances': (e['count'] as num).toInt() * 1,
            'police': (e['count'] as num).toInt() * 2,
            'fire_trucks': (e['count'] as num).toInt() * 3,
         }
      }).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error, style: GoogleFonts.outfit(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = '';
                  });
                  _refreshData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildConfidenceCards(),
              const SizedBox(height: 24),
              _buildCrisesChart(),
              const SizedBox(height: 24),
              _buildResourcesChart(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Crisis Analytics',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'System-wide metrics and resource utilization',
          style: GoogleFonts.outfit(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceCards() {
    final avgConf = _data['avg_confidence'] as Map<String, dynamic>? ?? {};
    final fireConf = (avgConf['fire'] as num?)?.toDouble() ?? 0.0;
    final smokeConf = (avgConf['smoke'] as num?)?.toDouble() ?? 0.0;
    final crisesPerDay = _data['crises_per_day'] as List<dynamic>? ?? [];
    int totalToday = 0;
    if (crisesPerDay.isNotEmpty) {
      totalToday = (crisesPerDay.last['count'] as num).toInt();
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildMetricCard('Total Crises Today', '$totalToday', AppColors.primary)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildMetricCard('Fire Avg Confidence', '${(fireConf * 100).toStringAsFixed(1)}%', AppColors.agentClassifier)),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricCard('Smoke Avg Confidence', '${(smokeConf * 100).toStringAsFixed(1)}%', AppColors.agentFusion)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrisesChart() {
    final crises = _data['crises_per_day'] as List<dynamic>? ?? [];
    if (crises.isEmpty) return const SizedBox();

    return _buildChartCard(
      title: 'Crises Over Last 7 Days',
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _getMaxY(crises, 'count') + 2,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < crises.length) {
                    final dateStr = crises[value.toInt()]['date'] as String;
                    final day = dateStr.substring(8); // get dd
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(day, style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(crises.length, (index) {
            final count = (crises[index]['count'] as num).toDouble();
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: count,
                  color: AppColors.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildResourcesChart() {
    final resources = _data['resources_per_day'] as List<dynamic>? ?? [];
    if (resources.isEmpty) return const SizedBox();

    double maxY = 0;
    for (var r in resources) {
      final allocs = r['allocations'] as Map<String, dynamic>;
      final a = (allocs['ambulances'] as num).toDouble();
      final p = (allocs['police'] as num).toDouble();
      final f = (allocs['fire_trucks'] as num).toDouble();
      if (a + p + f > maxY) maxY = a + p + f;
    }

    return _buildChartCard(
      title: 'Resources Allocated (Last 7 Days)',
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + 5,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < resources.length) {
                    final dateStr = resources[value.toInt()]['date'] as String;
                    final day = dateStr.substring(8);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(day, style: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 12)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(resources.length, (index) {
            final allocs = resources[index]['allocations'] as Map<String, dynamic>;
            final a = (allocs['ambulances'] as num).toDouble();
            final p = (allocs['police'] as num).toDouble();
            final f = (allocs['fire_trucks'] as num).toDouble();
            
            return BarChartGroupData(
              x: index,
              groupVertically: true,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: f,
                  color: AppColors.primary, // Red
                  width: 16,
                  borderRadius: p == 0 && a == 0 ? const BorderRadius.vertical(top: Radius.circular(6)) : BorderRadius.zero,
                ),
                BarChartRodData(
                  fromY: f,
                  toY: f + p,
                  color: AppColors.info, // Blue
                  width: 16,
                  borderRadius: a == 0 ? const BorderRadius.vertical(top: Radius.circular(6)) : BorderRadius.zero,
                ),
                BarChartRodData(
                  fromY: f + p,
                  toY: f + p + a,
                  color: AppColors.success, // Green
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  double _getMaxY(List<dynamic> data, String key) {
    double max = 0;
    for (var item in data) {
      if (item[key] != null) {
        final val = (item[key] as num).toDouble();
        if (val > max) max = val;
      }
    }
    return max;
  }

  Widget _buildChartCard({required String title, required Widget child}) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          Expanded(child: child),
          const SizedBox(height: 12),
          if (title.contains('Resources'))
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Fire Trucks', AppColors.primary),
                const SizedBox(width: 12),
                _buildLegendItem('Police', AppColors.info),
                const SizedBox(width: 12),
                _buildLegendItem('Ambulances', AppColors.success),
              ],
            ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

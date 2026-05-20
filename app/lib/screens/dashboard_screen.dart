import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../theme/app_colors.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;

  // Computed Stats
  int _totalDetections = 0;
  int _escalatedAlerts = 0;
  double _avgConfidence = 0.0;
  double _fireRate = 0.0;
  List<FlSpot> _confidenceHistory = [];

  @override
  void initState() {
    super.initState();
    _loadAndComputeStats();
  }

  Future<void> _loadAndComputeStats() async {
    setState(() => _loading = true);
    try {
      // Instead of relying on a missing /stats endpoint, we aggregate from the traces we already have!
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/traces'));

      if (response.statusCode == 200) {
        final List<dynamic> traces = json.decode(response.body);

        if (traces.isNotEmpty) {
          int escalated = 0;
          double totalConf = 0;
          List<FlSpot> spots = [];

          // Process up to the 15 most recent traces for the chart
          final recentTraces = traces.take(15).toList().reversed.toList();

          for (int i = 0; i < recentTraces.length; i++) {
            final trace = recentTraces[i];
            final conf = (trace['confidence_after'] as num?)?.toDouble() ?? 0.0;
            totalConf += conf;

            // Count traces that required high-level action or were flagged
            if (conf > 0.6 || trace['step_type'] == 'EVALUATE') {
              escalated++;
            }

            spots.add(FlSpot(i.toDouble(), conf * 100));
          }

          setState(() {
            _totalDetections = traces.length;
            _escalatedAlerts = escalated;
            _avgConfidence = (totalConf / recentTraces.length) * 100;
            _fireRate = (escalated / traces.length) * 100;
            _confidenceHistory = spots;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load stats: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Analytics Dashboard',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 16))
          : RefreshIndicator(
              onRefresh: _loadAndComputeStats,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'System Overview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats Grid
                    Row(
                      children: [
                        _buildStatCard(
                          'Total Detections',
                          _totalDetections.toString(),
                          Icons.history,
                          AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Escalated Alerts',
                          _escalatedAlerts.toString(),
                          Icons.warning_amber_rounded,
                          AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildStatCard(
                          'Avg Confidence',
                          '${_avgConfidence.toStringAsFixed(1)}%',
                          Icons.analytics_outlined,
                          AppColors.success,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Action Rate',
                          '${_fireRate.toStringAsFixed(1)}%',
                          Icons.local_fire_department_outlined,
                          AppColors.primary,
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    const Text(
                      'Confidence History (Last 15 Events)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Chart Card
                    Container(
                      height: 250,
                      padding: const EdgeInsets.only(
                        right: 24,
                        left: 8,
                        top: 24,
                        bottom: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _confidenceHistory.isEmpty
                          ? const Center(
                              child: Text(
                                'Not enough data to graph.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            )
                          : LineChart(_buildConfidenceChart()),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildConfidenceChart() {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ), // Hide X axis numbers for clean look
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}%',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (_confidenceHistory.length - 1).toDouble() > 0
          ? (_confidenceHistory.length - 1).toDouble()
          : 1,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        LineChartBarData(
          spots: _confidenceHistory,
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) =>
                FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.surface,
                  strokeWidth: 2,
                  strokeColor: AppColors.primary,
                ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.3),
                AppColors.primary.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

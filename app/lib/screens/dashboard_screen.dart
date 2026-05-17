import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map stats = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    setState(() => loading = true);
    try {
      var response = await http.get(Uri.parse('http://localhost:8000/stats'));
      if (response.statusCode == 200) {
        setState(() => stats = json.decode(response.body));
      }
    } catch (e) {}
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dashboard'), backgroundColor: Colors.red),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Stats cards
                  Row(children: [
                    _buildStatCard('Total Detections', stats['total'] ?? 0, Icons.history),
                    _buildStatCard('Fire Alerts', stats['fire_count'] ?? 0, Icons.warning),
                  ]),
                  SizedBox(height: 16),
                  Row(children: [
                    _buildStatCard('Avg Confidence', '${((stats['avg_confidence'] ?? 0) * 100).toStringAsFixed(1)}%', Icons.trending_up),
                    _buildStatCard('Fire Rate', '${((stats['fire_rate'] ?? 0) * 100).toStringAsFixed(1)}%', Icons.analytics),
                  ]),
                  SizedBox(height: 24),
                  // Confidence chart
                  Container(
                    height: 200,
                    child: LineChart(_buildConfidenceChart()),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: loadStats,
        child: Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildStatCard(String title, dynamic value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: Colors.red),
              SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 12)),
              Text(value.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  LineChartData _buildConfidenceChart() {
    return LineChartData(
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(show: true),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: (stats['confidence_history'] as List? ?? []).map((e) => FlSpot(e['index'].toDouble(), e['value'])).toList(),
          isCurved: true,
          color: Colors.red,
          barWidth: 3,
        ),
      ],
    );
  }
}

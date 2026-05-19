/// simulation_panel.dart
/// ---------------------
/// Reusable before/after comparison panel used by both the Incidents detail
/// dialog and the Monitoring Hub simulation section.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class SimulationPanel extends StatelessWidget {
  /// Parsed response from POST /simulate
  final Map<String, dynamic> simResult;

  const SimulationPanel({super.key, required this.simResult});

  // ── before/after column ──────────────────────────────────────────────────
  Widget _stateColumn({
    required String label,
    required Map<String, dynamic> state,
    required Color accentColor,
    required IconData headerIcon,
  }) {
    final rows = <Map<String, dynamic>>[
      {
        'key': 'Population',
        'val': state['affected_population']?.toString() ?? '—',
        'icon': Icons.people_alt_rounded,
      },
      {
        'key': 'Congestion',
        'val': (state['traffic_congestion'] as String? ?? '—').toUpperCase(),
        'icon': Icons.traffic_rounded,
      },
      {
        'key': 'Response',
        'val': (state['emergency_response'] as String? ?? '—')
            .replaceAll('_', ' ')
            .toUpperCase(),
        'icon': Icons.local_hospital_rounded,
      },
      {
        'key': 'Damage',
        'val': (state['estimated_damage'] as String? ?? '—').toUpperCase(),
        'icon': Icons.bar_chart_rounded,
      },
      if (state.containsKey('improvement'))
        {
          'key': 'Improvement',
          'val': state['improvement'] as String,
          'icon': Icons.trending_down_rounded,
        },
    ];

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.4), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Column header
            Row(
              children: [
                Icon(headerIcon, color: accentColor, size: 18),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(r['icon'] as IconData,
                            size: 13,
                            color: AppColors.textPrimary.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text(
                          r['key'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: AppColors.textPrimary.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      r['val'] as String,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── impact chips ─────────────────────────────────────────────────────────
  Widget _impactChips(Map<String, dynamic> metrics) {
    final chips = <Map<String, dynamic>>[
      {
        'label': '${metrics['response_time_improvement_pct']}% faster',
        'icon': Icons.speed_rounded,
        'color': Colors.greenAccent,
      },
      {
        'label': '${metrics['population_protected']} protected',
        'icon': Icons.shield_rounded,
        'color': Colors.blueAccent,
      },
      {
        'label': '${metrics['total_resources_deployed']} deployed',
        'icon': Icons.local_fire_department_rounded,
        'color': Colors.orangeAccent,
      },
      if (metrics['congestion_reduced'] == true)
        {
          'label': 'Congestion ↓',
          'icon': Icons.directions_car_rounded,
          'color': Colors.purpleAccent,
        },
      if (metrics['damage_downgraded'] == true)
        {
          'label': 'Damage ↓',
          'icon': Icons.trending_down_rounded,
          'color': Colors.tealAccent,
        },
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: chips.map((c) {
        final color = c['color'] as Color;
        return Chip(
          avatar: Icon(c['icon'] as IconData, size: 13, color: color),
          label: Text(
            c['label'] as String,
            style: GoogleFonts.outfit(fontSize: 11, color: color),
          ),
          backgroundColor: color.withOpacity(0.12),
          side: BorderSide(color: color.withOpacity(0.4), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final before = simResult['before'] as Map<String, dynamic>;
    final after = simResult['after'] as Map<String, dynamic>;
    final metrics = simResult['impact_metrics'] as Map<String, dynamic>? ??
        simResult['impact_metrics'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    final simSecs = simResult['simulation_time_seconds'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Colors.cyanAccent.withOpacity(0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel title
          Row(
            children: [
              const Icon(Icons.play_circle_fill_rounded,
                  color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 7),
              Text(
                'Simulation Result',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (simSecs != null)
                Text(
                  '${simSecs}s',
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.textPrimary.withOpacity(0.5)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Before / After side-by-side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stateColumn(
                label: 'BEFORE',
                state: before,
                accentColor: Colors.redAccent,
                headerIcon: Icons.warning_amber_rounded,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 36),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.cyanAccent.withOpacity(0.8),
                  size: 22,
                ),
              ),
              _stateColumn(
                label: 'AFTER',
                state: after,
                accentColor: Colors.greenAccent,
                headerIcon: Icons.check_circle_rounded,
              ),
            ],
          ),

          if (metrics.isNotEmpty) ...[ 
            const SizedBox(height: 12),
            Divider(color: Colors.white.withOpacity(0.07)),
            const SizedBox(height: 8),
            Text(
              'Impact Metrics',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AppColors.textPrimary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 6),
            _impactChips(metrics),
          ],
        ],
      ),
    );
  }
}

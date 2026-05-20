import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../config/api_config.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';

class TraceLog {
  final String? agentName;
  final String? stepType;
  final String? reasoning;
  final double? confidenceBefore;
  final double? confidenceAfter;
  final String? timestamp;
  bool isExpanded;

  TraceLog({
    this.agentName,
    this.stepType,
    this.reasoning,
    this.confidenceBefore,
    this.confidenceAfter,
    this.timestamp,
    this.isExpanded = false,
  });

  factory TraceLog.fromJson(Map<String, dynamic>? j) {
    if (j == null) return TraceLog();
    return TraceLog(
      agentName: j['agent_name']?.toString() ?? 'Unknown',
      stepType: (j['step_type']?.toString() ?? 'UNKNOWN').toUpperCase(),
      reasoning: j['reasoning']?.toString() ?? '',
      confidenceBefore: j['confidence_before'] != null ? (j['confidence_before'] as num).toDouble() : null,
      confidenceAfter: j['confidence_after'] != null ? (j['confidence_after'] as num).toDouble() : null,
      timestamp: j['timestamp']?.toString() ?? '',
    );
  }

  double? get delta {
    if (confidenceAfter != null && confidenceBefore != null) {
      return confidenceAfter! - confidenceBefore!;
    }
    return null;
  }
}

const _kSteps = ['OBSERVE', 'ANALYZE', 'DECIDE', 'ACT', 'EVALUATE'];

const _kStepColors = {
  'OBSERVE': AppColors.info,
  'ANALYZE': AppColors.agentSimulator,
  'DECIDE': AppColors.agentAllocator,
  'ACT': AppColors.error,
  'EVALUATE': AppColors.success,
};

const _kStepIcons = {
  'OBSERVE': Icons.visibility_outlined,
  'ANALYZE': Icons.analytics_outlined,
  'DECIDE': Icons.check_circle_outline,
  'ACT': Icons.flash_on_outlined,
  'EVALUATE': Icons.bar_chart_outlined,
};

class AgentTracesScreen extends StatefulWidget {
  const AgentTracesScreen({super.key});

  @override
  State<AgentTracesScreen> createState() => _AgentTracesScreenState();
}

class _AgentTracesScreenState extends State<AgentTracesScreen> with SingleTickerProviderStateMixin {
  List<TraceLog> _traces = [];
  bool _loading = true;
  Timer? _timer;
  StreamSubscription? _eventSub;

  late final AnimationController _progressCtrl;
  late final Animation<double> _progressAnim;

  int _activeStep = -1;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _progressAnim = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeInOut,
    );

    _fetchTraces();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchTraces());

    _eventSub = EventBus().stream.listen((event) {
      if (mounted) _fetchTraces();
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _timer?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTraces() async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/traces')).timeout(const Duration(seconds: 5));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = json.decode(res.body) as List<dynamic>?;
        if (raw == null) {
          setState(() => _loading = false);
          return;
        }

        final fetched = raw
            .map((e) => TraceLog.fromJson(e as Map<String, dynamic>?))
            .toList()
          ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));

        final expandMap = {for (final t in _traces) t.timestamp: t.isExpanded};
        for (final t in fetched) {
          t.isExpanded = expandMap[t.timestamp] ?? false;
        }

        setState(() {
          _traces = fetched;
          _loading = false;
        });

        if (fetched.isNotEmpty) {
          _animatePipeline(fetched.first.stepType);
        } else {
          setState(() => _activeStep = -1);
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _animatePipeline(String? stepType) {
    if (stepType == null) return;
    final idx = _kSteps.indexOf(stepType);
    if (idx == -1) return;
    setState(() => _activeStep = idx);
    final target = (idx + 1) / _kSteps.length;
    _progressCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  Color _bg(bool dark) => dark ? const Color(0xFF121212) : AppColors.background;
  Color _surface(bool dark) => dark ? const Color(0xFF1E1E1E) : AppColors.surface;
  Color _label(bool dark) => dark ? Colors.white : AppColors.textPrimary;
  Color _secondary(bool dark) => dark ? const Color(0xFFAAAAAA) : AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasTraces = _traces.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg(dark),
      body: SafeArea(
        child: _loading
            ? _buildLoading(dark)
            : !hasTraces
                ? _buildEmpty(dark)
                : _buildContent(dark),
      ),
    );
  }

  Widget _buildLoading(bool dark) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          color: dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_outlined, size: 56, color: _secondary(dark)),
            const SizedBox(height: 20),
            Text(
              'No traces yet',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: _label(dark),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload an image and click Detect\nto start the pipeline.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: _secondary(dark),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool dark) {
    return RefreshIndicator(
      onRefresh: _fetchTraces,
      color: AppColors.primary,
      backgroundColor: _surface(dark),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Agent Pipeline',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _label(dark),
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PipelineRow(
                activeStep: _activeStep,
                progressAnim: _progressAnim,
                dark: dark,
                surface: _surface(dark),
                label: _label(dark),
                secondary: _secondary(dark),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final t = _traces[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TraceCard(
                    trace: t,
                    dark: dark,
                    surface: _surface(dark),
                    label: _label(dark),
                    secondary: _secondary(dark),
                    onTap: () => setState(() => t.isExpanded = !t.isExpanded),
                  ),
                );
              }, childCount: _traces.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.activeStep,
    required this.progressAnim,
    required this.dark,
    required this.surface,
    required this.label,
    required this.secondary,
  });

  final int activeStep;
  final Animation<double> progressAnim;
  final bool dark;
  final Color surface;
  final Color label;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: dark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProgressBar(anim: progressAnim, activeStep: activeStep, dark: dark),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_kSteps.length, (i) {
              final step = _kSteps[i];
              final isActive = activeStep == i;
              final isComplete = activeStep > i && activeStep != -1;
              final color = _kStepColors[step] ?? AppColors.primary;

              return _StepCapsule(
                step: step,
                icon: _kStepIcons[step] ?? Icons.circle,
                color: color,
                isActive: isActive,
                isComplete: isComplete,
                dark: dark,
                secondary: secondary,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.anim,
    required this.activeStep,
    required this.dark,
  });

  final Animation<double> anim;
  final int activeStep;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final colors = activeStep >= 0
        ? List.generate(activeStep + 1, (i) => _kStepColors[_kSteps[i]] ?? AppColors.primary)
        : <Color>[Colors.transparent, Colors.transparent];

    if (colors.length == 1) colors.add(colors.first);

    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Stack(
        children: [
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          FractionallySizedBox(
            widthFactor: anim.value,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCapsule extends StatelessWidget {
  const _StepCapsule({
    required this.step,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.isComplete,
    required this.dark,
    required this.secondary,
  });

  final String step;
  final IconData icon;
  final Color color;
  final bool isActive;
  final bool isComplete;
  final bool dark;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isActive ? 1.08 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isActive
                  ? color
                  : isComplete
                      ? color.withOpacity(0.15)
                      : (dark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(14),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.38),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
              border: isActive
                  ? null
                  : Border.all(
                      color: isComplete ? color.withOpacity(0.35) : Colors.transparent,
                      width: 1.2,
                    ),
            ),
            child: Icon(
              isComplete ? Icons.check_rounded : icon,
              size: 20,
              color: isActive
                  ? Colors.white
                  : isComplete
                      ? color
                      : secondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _shortLabel(step),
            style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? color : secondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  String _shortLabel(String s) => switch (s) {
        'OBSERVE' => 'OBSERVE',
        'ANALYZE' => 'ANALYZE',
        'DECIDE' => 'DECIDE',
        'ACT' => 'ACT',
        'EVALUATE' => 'EVAL',
        _ => s,
      };
}

class _TraceCard extends StatelessWidget {
  const _TraceCard({
    required this.trace,
    required this.dark,
    required this.surface,
    required this.label,
    required this.secondary,
    required this.onTap,
  });

  final TraceLog trace;
  final bool dark;
  final Color surface;
  final Color label;
  final Color secondary;
  final VoidCallback onTap;

  String _time(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw.length >= 5 ? raw.substring(0, 5) : raw;
    }
  }

  Color get _stepColor => _kStepColors[trace.stepType] ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final deltaValue = trace.delta;
    final hasBigDelta = deltaValue != null && deltaValue.abs() > 0.05;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          gradient: dark ? null : AppColors.cardGradient,
          boxShadow: [
            BoxShadow(
              color: dark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StepBadge(step: trace.stepType ?? 'UNKNOWN', color: _stepColor),
                const Spacer(),
                Text(
                  _time(trace.timestamp),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              trace.agentName ?? 'Unknown',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: label,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: Text(
                trace.reasoning ?? '',
                style: GoogleFonts.outfit(fontSize: 14, color: secondary, height: 1.45),
                maxLines: trace.isExpanded ? null : 2,
                overflow: trace.isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ConfidenceDot(value: trace.confidenceBefore ?? 0.0, color: secondary),
                const SizedBox(width: 6),
                Text(
                  trace.confidenceBefore != null ? '${(trace.confidenceBefore! * 100).toStringAsFixed(0)}%' : 'N/A',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: secondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 14, color: secondary),
                ),
                _ConfidenceDot(value: trace.confidenceAfter ?? 0.0, color: _stepColor),
                const SizedBox(width: 6),
                Text(
                  trace.confidenceAfter != null ? '${(trace.confidenceAfter! * 100).toStringAsFixed(0)}%' : 'N/A',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _stepColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasBigDelta) ...[
                  const Spacer(),
                  _DeltaBadge(delta: deltaValue!),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.step, required this.color});
  final String step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        step,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ConfidenceDot extends StatelessWidget {
  const _ConfidenceDot({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(value),
          ),
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});
  final double delta;

  @override
  Widget build(BuildContext context) {
    final isPos = delta > 0;
    final color = isPos ? AppColors.success : AppColors.error;
    final icon = isPos ? Icons.trending_up : Icons.trending_down;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '${isPos ? '+' : ''}${(delta * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// 타임라인 차트 + 범례 토글.
/// x = 시간(초). 채널별 surprise 5선 + 굵은 fused 선.
/// 하이라이트 peak_sec 위치에 수직선 + 순위 라벨.
class TimelineChart extends StatefulWidget {
  const TimelineChart({
    super.key,
    required this.timeline,
    required this.highlights,
    required this.durationSec,
  });

  final Timeline timeline;
  final List<Highlight> highlights;
  final double durationSec;

  /// 차트에 그릴 시리즈(표준 채널 + fused).
  static const List<String> series = [
    'frame_entropy',
    'motion',
    'spectral',
    'cheer',
    'loudness',
    'fused',
  ];

  /// 차트 렌더링 전 다운샘플링 목표 점 수.
  static const int targetPoints = 1500;

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  /// 시리즈 on/off 상태.
  final Map<String, bool> _visible = {
    for (final s in TimelineChart.series) s: true,
  };

  // 다운샘플된 데이터 캐시.
  List<double> _t = const [];
  Map<String, List<double>> _downsampled = const {};
  double _maxY = 1.0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant TimelineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.timeline, widget.timeline)) {
      _recompute();
    }
  }

  void _recompute() {
    final tl = widget.timeline;
    final n = tl.length;
    if (n == 0) {
      _t = const [];
      _downsampled = const {};
      _maxY = 1.0;
      return;
    }
    final stride = (n / TimelineChart.targetPoints).ceil().clamp(1, n);

    final t = <double>[];
    final out = <String, List<double>>{
      for (final s in TimelineChart.series) s: <double>[],
    };

    for (var i = 0; i < n; i += stride) {
      // stride 구간의 대표값으로 최댓값(피크 보존)을 사용.
      final end = (i + stride).clamp(0, n);
      t.add(tl.t[i]);
      for (final s in TimelineChart.series) {
        final arr = tl.series(s);
        var peak = double.negativeInfinity;
        for (var k = i; k < end && k < arr.length; k++) {
          if (arr[k] > peak) peak = arr[k];
        }
        out[s]!.add(peak.isFinite ? peak : 0.0);
      }
    }

    double maxY = 0.0;
    for (final s in TimelineChart.series) {
      for (final v in out[s]!) {
        if (v > maxY) maxY = v;
      }
    }
    if (maxY <= 0) maxY = 1.0;

    _t = t;
    _downsampled = out;
    _maxY = maxY * 1.08;
  }

  List<FlSpot> _spots(String channel) {
    final ys = _downsampled[channel];
    if (ys == null) return const [];
    final spots = <FlSpot>[];
    for (var i = 0; i < _t.length && i < ys.length; i++) {
      spots.add(FlSpot(_t[i], ys[i]));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    if (_t.isEmpty) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: Text(
            '타임라인 데이터가 없습니다',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final maxX = widget.durationSec > 0
        ? widget.durationSec
        : (_t.isNotEmpty ? _t.last : 1.0);
    final xInterval = (maxX / 6).clamp(1.0, double.infinity);

    final bars = <LineChartBarData>[];
    for (final s in TimelineChart.series) {
      if (_visible[s] != true) continue;
      final isFused = s == 'fused';
      bars.add(
        LineChartBarData(
          spots: _spots(s),
          isCurved: false,
          color: AppColors.forChannel(s),
          barWidth: isFused ? 2.8 : 1.2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    final vLines = <VerticalLine>[
      for (final h in widget.highlights)
        VerticalLine(
          x: h.peakSec,
          color: AppColors.warning.withValues(alpha: 0.55),
          strokeWidth: 1.2,
          dashArray: const [4, 3],
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.topCenter,
            style: const TextStyle(
              color: AppColors.warning,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            labelResolver: (_) => '#${h.rank}',
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Legend(visible: _visible, onToggle: _onToggle),
        const SizedBox(height: 12),
        SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: _maxY,
              clipData: const FlClipData.all(),
              lineBarsData: bars,
              extraLinesData: ExtraLinesData(verticalLines: vLines),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: (_maxY / 4).clamp(0.1, double.infinity),
                verticalInterval: xInterval,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.border, strokeWidth: 0.5),
                getDrawingVerticalLine: (_) =>
                    const FlLine(color: AppColors.border, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: AppColors.border),
                  left: BorderSide(color: AppColors.border),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text(
                    'surprise (bits)',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
                  axisNameSize: 18,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: (_maxY / 4).clamp(0.1, double.infinity),
                    getTitlesWidget: (value, meta) => Text(
                      value.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < 0 || value > maxX) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          formatMmss(value),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.surfaceAlt,
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                          s.y.toStringAsFixed(2),
                          TextStyle(
                            color: s.bar.color ?? AppColors.textPrimary,
                            fontSize: 10,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onToggle(String s) {
    setState(() => _visible[s] = !(_visible[s] ?? false));
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.visible, required this.onToggle});

  final Map<String, bool> visible;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final s in TimelineChart.series)
          _LegendChip(
            channel: s,
            active: visible[s] ?? false,
            onTap: () => onToggle(s),
          ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.channel,
    required this.active,
    required this.onTap,
  });

  final String channel;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forChannel(channel);
    final isFused = channel == 'fused';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.16) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : AppColors.border,
            width: active ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isFused ? 16 : 12,
              height: isFused ? 4 : 3,
              decoration: BoxDecoration(
                color: active ? color : AppColors.textSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              channelLabel(channel),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isFused ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

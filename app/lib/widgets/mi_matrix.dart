import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// 채널 패널: 가중치 막대 + 5x5 MI 히트맵.
class ChannelPanel extends StatelessWidget {
  const ChannelPanel({
    super.key,
    required this.channels,
    required this.miMatrix,
  });

  final List<ChannelStat> channels;
  final Map<String, Map<String, double>> miMatrix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('융합 가중치'),
        const SizedBox(height: 10),
        _WeightBars(channels: channels),
        const SizedBox(height: 24),
        const _SectionLabel('상호정보량 행렬 (MI)'),
        const SizedBox(height: 10),
        MiMatrixHeatmap(miMatrix: miMatrix),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _WeightBars extends StatelessWidget {
  const _WeightBars({required this.channels});
  final List<ChannelStat> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Text(
        '채널 정보 없음',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final maxW = channels.fold<double>(
      0.0,
      (m, c) => c.weight > m ? c.weight : m,
    );
    return Column(
      children: [
        for (final c in channels)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    c.labelKo.isNotEmpty ? c.labelKo : channelLabel(c.name),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxW > 0 ? (c.weight / maxW).clamp(0.0, 1.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.forChannel(c.name),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    c.weight.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 5x5 MI 히트맵. 값 0..1 색강도.
class MiMatrixHeatmap extends StatelessWidget {
  const MiMatrixHeatmap({super.key, required this.miMatrix});

  final Map<String, Map<String, double>> miMatrix;

  static const List<String> _short = [
    '엔트로피',
    '모션',
    '스펙트럼',
    '환호성',
    '음량',
  ];

  double _value(String row, String col) {
    final r = miMatrix[row];
    if (r == null) return double.nan;
    final v = r[col];
    if (v == null) return double.nan;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    // 표시할 최대값으로 정규화(대각 1.0 가정이 깨질 수 있으므로 안전 처리).
    double maxV = 0.0;
    for (final ch in kChannels) {
      for (final ch2 in kChannels) {
        final v = _value(ch, ch2);
        if (v.isFinite && v > maxV) maxV = v;
      }
    }
    if (maxV <= 0) maxV = 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const headerW = 64.0;
        final available = constraints.maxWidth - headerW;
        final cell = (available / kChannels.length).clamp(28.0, 56.0);

        Widget colHeader() => Row(
              children: [
                const SizedBox(width: headerW),
                for (var i = 0; i < kChannels.length; i++)
                  SizedBox(
                    width: cell,
                    child: Text(
                      _short[i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            colHeader(),
            const SizedBox(height: 4),
            for (var r = 0; r < kChannels.length; r++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: headerW,
                      child: Text(
                        _short[r],
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (var c = 0; c < kChannels.length; c++)
                      _MiCell(
                        size: cell,
                        value: _value(kChannels[r], kChannels[c]),
                        norm: maxV,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiCell extends StatelessWidget {
  const _MiCell({required this.size, required this.value, required this.norm});

  final double size;
  final double value;
  final double norm;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.isFinite;
    final t = hasValue ? (value / norm).clamp(0.0, 1.0) : 0.0;
    final bg = hasValue
        ? Color.lerp(AppColors.surfaceAlt, AppColors.accent, t)!
        : AppColors.surfaceAlt;
    final textColor = t > 0.55 ? Colors.white : AppColors.textSecondary;

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        hasValue ? value.toStringAsFixed(2) : '-',
        style: TextStyle(
          fontSize: 9,
          color: textColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

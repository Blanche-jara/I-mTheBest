import 'package:flutter/material.dart';

import '../theme.dart';

/// 채널별 기여(bits)를 가로 막대로 표시.
class ContributionBar extends StatelessWidget {
  const ContributionBar({super.key, required this.contributions});

  /// 채널명 -> 기여 bits.
  final Map<String, double> contributions;

  @override
  Widget build(BuildContext context) {
    // 표준 채널 순서로 정렬, 0 이상만 의미. 최대값으로 정규화.
    final entries = <MapEntry<String, double>>[];
    for (final ch in kChannels) {
      final v = contributions[ch] ?? 0.0;
      entries.add(MapEntry(ch, v < 0 ? 0.0 : v));
    }
    final maxVal = entries.fold<double>(
      0.0,
      (m, e) => e.value > m ? e.value : m,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    channelLabel(e.key),
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
                      value: maxVal > 0 ? (e.value / maxVal).clamp(0.0, 1.0) : 0.0,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceAlt,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.forChannel(e.key)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${e.value.toStringAsFixed(2)} b',
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

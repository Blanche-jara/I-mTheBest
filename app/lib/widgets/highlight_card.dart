import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'contribution_bar.dart';

/// 하이라이트 카드 — 썸네일, 순위 배지, 정보량, 주도채널, 요약, 기여 막대, 재생.
class HighlightCard extends StatelessWidget {
  const HighlightCard({
    super.key,
    required this.highlight,
    required this.onPlay,
  });

  final Highlight highlight;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final h = highlight;
    final ex = h.explanation;
    final canPlay = (h.clipPath != null && h.clipPath!.isNotEmpty);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(path: h.thumbnailPath, rank: h.rank),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatMmss(h.peakSec),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        icon: Icons.timelapse,
                        text: '${h.durationSec.toStringAsFixed(1)}초',
                      ),
                      const SizedBox(width: 6),
                      _Pill(
                        icon: Icons.bolt,
                        text: '정보량 ${ex.totalBits.toStringAsFixed(1)} bits',
                        accent: true,
                      ),
                      const Spacer(),
                      _DominantBadge(
                        channel: ex.dominantChannel,
                        labelKo: ex.dominantLabelKo.isNotEmpty
                            ? ex.dominantLabelKo
                            : channelLabel(ex.dominantChannel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ex.summaryKo.isNotEmpty ? ex.summaryKo : '설명 없음',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ContributionBar(contributions: ex.contributions),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: canPlay ? onPlay : null,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('재생'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.rank});

  final String? path;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null && path!.isNotEmpty && File(path!).existsSync();
    return SizedBox(
      width: 160,
      height: 100,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasFile
                ? Image.file(
                    File(path!),
                    width: 160,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const _ThumbPlaceholder(),
                  )
                : const _ThumbPlaceholder(),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#$rank',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 100,
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.textSecondary,
        size: 28,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.accent = false});

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.accent : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (accent ? AppColors.accent : AppColors.surfaceAlt)
            .withValues(alpha: accent ? 0.16 : 1.0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent ? AppColors.accent : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: accent ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _DominantBadge extends StatelessWidget {
  const _DominantBadge({required this.channel, required this.labelKo});

  final String channel;
  final String labelKo;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forChannel(channel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '주도: $labelKo',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

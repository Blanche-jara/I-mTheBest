import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/highlight_card.dart';
import '../widgets/mi_matrix.dart';
import '../widgets/player_view.dart';
import '../widgets/timeline_chart.dart';

/// 대시보드 — 핵심 산출물 화면.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.state,
    required this.result,
  });

  final AppState state;
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    // rank 정렬 사본.
    final highlights = [...result.highlights]
      ..sort((a, b) => a.rank.compareTo(b.rank));

    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 결과'),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: '새 분석',
          onPressed: () {
            state.reset();
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Header(result: result),
              const SizedBox(height: 16),
              _SectionCard(
                title: '타임라인 (채널별 surprise)',
                icon: Icons.show_chart,
                child: TimelineChart(
                  timeline: result.timeline,
                  highlights: highlights,
                  durationSec: result.durationSec,
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '채널 분석',
                icon: Icons.equalizer,
                child: ChannelPanel(
                  channels: result.channels,
                  miMatrix: result.miMatrix,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.star_outline,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '하이라이트 (${highlights.length}개)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (highlights.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '검출된 하이라이트가 없습니다',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                for (final h in highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: HighlightCard(
                      highlight: h,
                      onPlay: () => _play(context, h),
                    ),
                  ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context, Highlight h) {
    final path = h.clipPath;
    if (path == null || path.isEmpty) return;
    PlayerDialog.show(
      context,
      clipPath: path,
      title: '#${h.rank} · ${formatMmss(h.peakSec)}',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.result});
  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final frame = (result.frameWidth > 0 && result.frameHeight > 0)
        ? '${result.frameWidth}×${result.frameHeight}'
        : '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.movie_outlined,
                    size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.fileName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _Stat(
                  icon: Icons.schedule,
                  label: '길이',
                  value: formatMmss(result.durationSec),
                ),
                _Stat(
                  icon: Icons.speed,
                  label: '분석 FPS',
                  value: _fmt(result.analysisFps),
                ),
                _Stat(
                  icon: Icons.aspect_ratio,
                  label: '프레임 크기',
                  value: frame,
                ),
                _Stat(
                  icon: Icons.star,
                  label: '하이라이트',
                  value: '${result.highlights.length}개',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

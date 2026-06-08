import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../theme.dart';

/// media_kit 기반 클립 플레이어 다이얼로그.
/// 재생/일시정지/탐색/닫기.
class PlayerDialog extends StatefulWidget {
  const PlayerDialog({
    super.key,
    required this.clipPath,
    required this.title,
  });

  final String clipPath;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required String clipPath,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => PlayerDialog(clipPath: clipPath, title: title),
    );
  }

  @override
  State<PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<PlayerDialog> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  bool _playing = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    });
    _player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.open(Media(widget.clipPath));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds.clamp(0, totalMs <= 0 ? 0 : totalMs);

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        formatMmss(_position.inSeconds),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                            activeTrackColor: AppColors.primary,
                            inactiveTrackColor: AppColors.surfaceAlt,
                            thumbColor: AppColors.primary,
                          ),
                          child: Slider(
                            value: posMs.toDouble(),
                            min: 0,
                            max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                            onChanged: totalMs <= 0
                                ? null
                                : (v) => _player
                                    .seek(Duration(milliseconds: v.round())),
                          ),
                        ),
                      ),
                      Text(
                        formatMmss(_duration.inSeconds),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '10초 뒤로',
                        color: AppColors.textPrimary,
                        icon: const Icon(Icons.replay_10),
                        onPressed: () {
                          final target = _position - const Duration(seconds: 10);
                          _player.seek(
                              target < Duration.zero ? Duration.zero : target);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: _playing ? '일시정지' : '재생',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => _player.playOrPause(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '10초 앞으로',
                        color: AppColors.textPrimary,
                        icon: const Icon(Icons.forward_10),
                        onPressed: () =>
                            _player.seek(_position + const Duration(seconds: 10)),
                      ),
                    ],
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

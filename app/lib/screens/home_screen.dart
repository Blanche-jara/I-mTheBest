import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'analysis_screen.dart';

/// 홈: 서버 연결, 영상 선택, 파라미터, 분석 시작.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.state.baseUrl);

  // 파라미터 입력 컨트롤러.
  late final TextEditingController _fpsCtrl =
      TextEditingController(text: _fmt(widget.state.params.analysisFps));
  late final TextEditingController _topKCtrl =
      TextEditingController(text: '${widget.state.params.topK}');
  late final TextEditingController _gapCtrl =
      TextEditingController(text: _fmt(widget.state.params.minGapSec));
  late final TextEditingController _zCtrl =
      TextEditingController(text: _fmt(widget.state.params.peakZ));
  late final TextEditingController _minClipCtrl =
      TextEditingController(text: _fmt(widget.state.params.minClipSec));
  late final TextEditingController _maxClipCtrl =
      TextEditingController(text: _fmt(widget.state.params.maxClipSec));
  late final TextEditingController _padCtrl =
      TextEditingController(text: _fmt(widget.state.params.clipPadSec));
  bool _reencode = true;

  bool _starting = false;
  String? _startError;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void initState() {
    super.initState();
    _reencode = widget.state.params.reencodeClips;
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _urlCtrl.dispose();
    _fpsCtrl.dispose();
    _topKCtrl.dispose();
    _gapCtrl.dispose();
    _zCtrl.dispose();
    _minClipCtrl.dispose();
    _maxClipCtrl.dispose();
    _padCtrl.dispose();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _pickVideo() async {
    const typeGroup = XTypeGroup(
      label: '영상',
      extensions: ['mp4', 'mkv', 'mov', 'avi', 'webm'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file != null) {
      widget.state.setVideoPath(file.path);
    }
  }

  AnalysisParams _collectParams() {
    return AnalysisParams(
      analysisFps: double.tryParse(_fpsCtrl.text.trim()) ?? 3.0,
      topK: int.tryParse(_topKCtrl.text.trim()) ?? 12,
      minGapSec: double.tryParse(_gapCtrl.text.trim()) ?? 8.0,
      peakZ: double.tryParse(_zCtrl.text.trim()) ?? 1.2,
      minClipSec: double.tryParse(_minClipCtrl.text.trim()) ?? 12.0,
      maxClipSec: double.tryParse(_maxClipCtrl.text.trim()) ?? 30.0,
      clipPadSec: double.tryParse(_padCtrl.text.trim()) ?? 4.0,
      reencodeClips: _reencode,
    );
  }

  Future<void> _start() async {
    final state = widget.state;
    if (state.videoPath == null) {
      setState(() => _startError = '먼저 영상을 선택하세요');
      return;
    }
    setState(() {
      _starting = true;
      _startError = null;
    });
    state.baseUrl = _urlCtrl.text.trim();
    state.setParams(_collectParams());
    try {
      final jobId = await state.startAnalysis();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AnalysisScreen(state: state, jobId: jobId),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _startError = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppColors.accent),
            SizedBox(width: 10),
            Text('하이라이트 스튜디오',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ServerSection(
                  urlCtrl: _urlCtrl,
                  checking: state.checkingHealth,
                  health: state.health,
                  error: state.healthError,
                  onCheck: () {
                    state.baseUrl = _urlCtrl.text.trim();
                    state.checkHealth();
                  },
                ),
                const SizedBox(height: 16),
                _VideoSection(
                  fileName: state.videoFileName,
                  path: state.videoPath,
                  onPick: _pickVideo,
                ),
                const SizedBox(height: 16),
                _ParamsSection(
                  fpsCtrl: _fpsCtrl,
                  topKCtrl: _topKCtrl,
                  gapCtrl: _gapCtrl,
                  zCtrl: _zCtrl,
                  minClipCtrl: _minClipCtrl,
                  maxClipCtrl: _maxClipCtrl,
                  padCtrl: _padCtrl,
                  reencode: _reencode,
                  onReencode: (v) => setState(() => _reencode = v),
                ),
                const SizedBox(height: 20),
                if (_startError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ErrorBanner(message: _startError!),
                  ),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: (_starting || state.videoPath == null)
                        ? null
                        : _start,
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_circle_outline),
                    label: Text(_starting ? '시작 중...' : '분석 시작'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({
    required this.urlCtrl,
    required this.checking,
    required this.health,
    required this.error,
    required this.onCheck,
  });

  final TextEditingController urlCtrl;
  final bool checking;
  final HealthInfo? health;
  final String? error;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '서버',
      icon: Icons.dns_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: '서버 URL',
                    hintText: 'http://127.0.0.1:8000',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: checking ? null : onCheck,
                  icon: checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('서버 연결확인'),
                ),
              ),
            ],
          ),
          if (health != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _StatusChip(
                  label: 'python',
                  value: health!.python,
                ),
                _StatusChip(label: 'opencv', value: health!.opencv),
                _StatusChip(label: 'librosa', value: health!.librosa),
                _StatusChip(
                  label: 'cuda',
                  value: health!.cuda ? (health!.device ?? 'on') : 'off',
                  ok: health!.cuda,
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: '연결 실패: $error'),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value, this.ok});

  final String label;
  final String? value;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final available = value != null && value!.isNotEmpty && value != 'off';
    final good = ok ?? available;
    final color = good ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
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
            '$label: ${available ? value : '없음'}',
            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _VideoSection extends StatelessWidget {
  const _VideoSection({
    required this.fileName,
    required this.path,
    required this.onPick,
  });

  final String? fileName;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '영상',
      icon: Icons.video_file_outlined,
      child: Row(
        children: [
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('영상 선택'),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: fileName == null
                ? const Text(
                    '선택된 영상이 없습니다 (mp4/mkv/mov/avi/webm)',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        path ?? '',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ParamsSection extends StatelessWidget {
  const _ParamsSection({
    required this.fpsCtrl,
    required this.topKCtrl,
    required this.gapCtrl,
    required this.zCtrl,
    required this.minClipCtrl,
    required this.maxClipCtrl,
    required this.padCtrl,
    required this.reencode,
    required this.onReencode,
  });

  final TextEditingController fpsCtrl;
  final TextEditingController topKCtrl;
  final TextEditingController gapCtrl;
  final TextEditingController zCtrl;
  final TextEditingController minClipCtrl;
  final TextEditingController maxClipCtrl;
  final TextEditingController padCtrl;
  final bool reencode;
  final ValueChanged<bool> onReencode;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '분석 파라미터',
      icon: Icons.tune,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: fpsCtrl,
                  label: '분석 FPS',
                  helper: '초당 분석 프레임',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: topKCtrl,
                  label: '하이라이트 수 (top_k)',
                  helper: '최대 개수',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: gapCtrl,
                  label: '최소 간격(초)',
                  helper: 'min_gap_sec',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: zCtrl,
                  label: '피크 임계 z (peak_z)',
                  helper: 'mean + z·std',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: minClipCtrl,
                  label: '클립 최소 길이(초)',
                  helper: 'min_clip_sec',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumField(
                  controller: maxClipCtrl,
                  label: '클립 최대 길이(초)',
                  helper: 'max_clip_sec',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  controller: padCtrl,
                  label: '피크 앞뒤 여유(초)',
                  helper: 'clip_pad_sec · 클립이 짧으면 이 값을 올리세요',
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '클립 재인코딩 (reencode_clips)',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary),
                      ),
                      Text(
                        '켜면 프레임 정확 컷, 끄면 빠른 copy',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(value: reencode, onChanged: onReencode),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.controller,
    required this.label,
    required this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, helperText: helper),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

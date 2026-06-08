import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

/// 분석 진행 화면 — WS 스트림(실패 시 폴링 폴백).
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.state,
    required this.jobId,
  });

  final AppState state;
  final String jobId;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  StreamSubscription<JobStatus>? _wsSub;
  Timer? _pollTimer;
  Timer? _elapsedTimer;

  final Stopwatch _stopwatch = Stopwatch();

  double _progress = 0.0;
  String _stage = '대기 중';
  String _message = '';
  String _status = 'queued';
  String? _error;
  bool _navigated = false;
  bool _usingPolling = false;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _connectWs();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _pollTimer?.cancel();
    _elapsedTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _connectWs() {
    _wsSub = widget.state.client.watch(widget.jobId).listen(
      _applyStatus,
      onError: (Object e) {
        // WS 연결/스트림 실패 -> 폴링 폴백.
        _startPolling();
      },
      onDone: () {
        // 스트림이 terminal 없이 닫혔고 아직 끝나지 않았으면 폴링.
        if (!_navigated && _error == null && !_isTerminal(_status)) {
          _startPolling();
        }
      },
      cancelOnError: true,
    );
  }

  void _startPolling() {
    if (_usingPolling || _navigated) return;
    _usingPolling = true;
    _wsSub?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      try {
        final s = await widget.state.client.jobStatus(widget.jobId);
        _applyStatus(s);
      } catch (e) {
        if (mounted) {
          setState(() => _message = '폴링 오류: $e');
        }
      }
    });
  }

  bool _isTerminal(String s) => s == 'done' || s == 'error';

  void _applyStatus(JobStatus s) {
    if (!mounted || _navigated) return;
    setState(() {
      _progress = s.progress.clamp(0.0, 1.0);
      _stage = s.stage.isNotEmpty ? s.stage : _stage;
      _message = s.message;
      _status = s.status;
      if (s.isError) {
        _error = s.error ?? '알 수 없는 오류';
      }
    });

    if (s.isDone) {
      _onDone(s.result);
    } else if (s.isError) {
      _stopwatch.stop();
      _pollTimer?.cancel();
      _wsSub?.cancel();
    }
  }

  Future<void> _onDone(AnalysisResult? embedded) async {
    if (_navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _stopwatch.stop();

    AnalysisResult? result = embedded;
    try {
      // WS 진행 이벤트엔 result 가 없으므로 명시적으로 가져온다.
      result ??= await widget.state.client.jobResult(widget.jobId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _navigated = false;
          _error = '결과를 불러오지 못했습니다: $e';
        });
      }
      return;
    }

    widget.state.setResult(result);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(state: widget.state, result: result!),
      ),
    );
  }

  String get _elapsedText {
    final s = _stopwatch.elapsed.inSeconds;
    return formatMmss(s);
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).toStringAsFixed(0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 진행'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '홈으로',
          onPressed: () {
            widget.state.reset();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error != null
                ? _ErrorView(
                    message: _error!,
                    onHome: () {
                      widget.state.reset();
                      Navigator.of(context).pop();
                    },
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insights, color: AppColors.accent),
                          const SizedBox(width: 10),
                          Text(
                            '$pct%',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          _Tag(
                            text: _usingPolling ? '폴링' : '실시간',
                            color: _usingPolling
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          minHeight: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _InfoRow(label: '단계', value: _stage),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: '메시지',
                        value: _message.isEmpty ? '-' : _message,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(label: '경과 시간', value: _elapsedText),
                      const SizedBox(height: 8),
                      _InfoRow(label: '작업 ID', value: widget.jobId),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onHome});
  final String message;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
        const SizedBox(height: 16),
        const Text(
          '분석에 실패했습니다',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onHome,
          icon: const Icon(Icons.home_outlined),
          label: const Text('홈으로 돌아가기'),
        ),
      ],
    );
  }
}

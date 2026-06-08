// Dart 데이터 모델 — engine/models.py 의 pydantic 스키마와 1:1 대응.
// JSON 키는 snake_case 그대로.

double _toDouble(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _toInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

List<double> _toDoubleList(dynamic v) {
  if (v is List) {
    return v.map((e) => _toDouble(e)).toList(growable: false);
  }
  return const [];
}

/// 시계열 — 시간축 t 와 채널별 surprise(bits). 모든 배열 길이 동일.
class Timeline {
  final List<double> t;
  final List<double> frameEntropy;
  final List<double> motion;
  final List<double> spectral;
  final List<double> cheer;
  final List<double> loudness;
  final List<double> fused;

  const Timeline({
    required this.t,
    required this.frameEntropy,
    required this.motion,
    required this.spectral,
    required this.cheer,
    required this.loudness,
    required this.fused,
  });

  factory Timeline.fromJson(Map<String, dynamic> j) => Timeline(
        t: _toDoubleList(j['t']),
        frameEntropy: _toDoubleList(j['frame_entropy']),
        motion: _toDoubleList(j['motion']),
        spectral: _toDoubleList(j['spectral']),
        cheer: _toDoubleList(j['cheer']),
        loudness: _toDoubleList(j['loudness']),
        fused: _toDoubleList(j['fused']),
      );

  /// 채널명 -> 해당 시계열 배열.
  List<double> series(String channel) {
    switch (channel) {
      case 'frame_entropy':
        return frameEntropy;
      case 'motion':
        return motion;
      case 'spectral':
        return spectral;
      case 'cheer':
        return cheer;
      case 'loudness':
        return loudness;
      case 'fused':
        return fused;
      default:
        return const [];
    }
  }

  int get length => t.length;
}

/// 채널 통계 — 가중치, MI, 평균/피크.
class ChannelStat {
  final String name;
  final String labelKo;
  final String group; // "video" | "audio"
  final double weight;
  final double meanBits;
  final double peakBits;
  final double miWithFused;

  const ChannelStat({
    required this.name,
    required this.labelKo,
    required this.group,
    required this.weight,
    required this.meanBits,
    required this.peakBits,
    required this.miWithFused,
  });

  factory ChannelStat.fromJson(Map<String, dynamic> j) => ChannelStat(
        name: (j['name'] ?? '').toString(),
        labelKo: (j['label_ko'] ?? '').toString(),
        group: (j['group'] ?? '').toString(),
        weight: _toDouble(j['weight']),
        meanBits: _toDouble(j['mean_bits']),
        peakBits: _toDouble(j['peak_bits']),
        miWithFused: _toDouble(j['mi_with_fused']),
      );
}

/// 하이라이트 설명 — 정보량과 채널별 기여.
class HighlightExplanation {
  final double totalBits;
  final Map<String, double> contributions;
  final String dominantChannel;
  final String dominantLabelKo;
  final String summaryKo;

  const HighlightExplanation({
    required this.totalBits,
    required this.contributions,
    required this.dominantChannel,
    required this.dominantLabelKo,
    required this.summaryKo,
  });

  factory HighlightExplanation.fromJson(Map<String, dynamic> j) {
    final raw = j['contributions'];
    final contrib = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) => contrib[k.toString()] = _toDouble(v));
    }
    return HighlightExplanation(
      totalBits: _toDouble(j['total_bits']),
      contributions: contrib,
      dominantChannel: (j['dominant_channel'] ?? '').toString(),
      dominantLabelKo: (j['dominant_label_ko'] ?? '').toString(),
      summaryKo: (j['summary_ko'] ?? '').toString(),
    );
  }
}

/// 하이라이트 1건.
class Highlight {
  final String id;
  final int rank;
  final double startSec;
  final double endSec;
  final double peakSec;
  final double score;
  final HighlightExplanation explanation;
  final String? clipPath;
  final String? clipUrl;
  final String? thumbnailPath;
  final String? thumbnailUrl;

  const Highlight({
    required this.id,
    required this.rank,
    required this.startSec,
    required this.endSec,
    required this.peakSec,
    required this.score,
    required this.explanation,
    this.clipPath,
    this.clipUrl,
    this.thumbnailPath,
    this.thumbnailUrl,
  });

  double get durationSec => (endSec - startSec).abs();

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: (j['id'] ?? '').toString(),
        rank: _toInt(j['rank']),
        startSec: _toDouble(j['start_sec']),
        endSec: _toDouble(j['end_sec']),
        peakSec: _toDouble(j['peak_sec']),
        score: _toDouble(j['score']),
        explanation: HighlightExplanation.fromJson(
          (j['explanation'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        clipPath: j['clip_path'] as String?,
        clipUrl: j['clip_url'] as String?,
        thumbnailPath: j['thumbnail_path'] as String?,
        thumbnailUrl: j['thumbnail_url'] as String?,
      );
}

/// 전체 분석 결과.
class AnalysisResult {
  final String videoPath;
  final double durationSec;
  final double analysisFps;
  final List<int> frameSize; // [w, h]
  final Timeline timeline;
  final List<ChannelStat> channels;
  final List<Highlight> highlights;
  final Map<String, dynamic> params;
  final Map<String, Map<String, double>> miMatrix;

  const AnalysisResult({
    required this.videoPath,
    required this.durationSec,
    required this.analysisFps,
    required this.frameSize,
    required this.timeline,
    required this.channels,
    required this.highlights,
    required this.params,
    required this.miMatrix,
  });

  String get fileName {
    final p = videoPath.replaceAll('\\', '/');
    final idx = p.lastIndexOf('/');
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  int get frameWidth => frameSize.isNotEmpty ? frameSize[0] : 0;
  int get frameHeight => frameSize.length > 1 ? frameSize[1] : 0;

  factory AnalysisResult.fromJson(Map<String, dynamic> j) {
    final mi = <String, Map<String, double>>{};
    final rawMi = j['mi_matrix'];
    if (rawMi is Map) {
      rawMi.forEach((row, cols) {
        final inner = <String, double>{};
        if (cols is Map) {
          cols.forEach((c, v) => inner[c.toString()] = _toDouble(v));
        }
        mi[row.toString()] = inner;
      });
    }

    return AnalysisResult(
      videoPath: (j['video_path'] ?? '').toString(),
      durationSec: _toDouble(j['duration_sec']),
      analysisFps: _toDouble(j['analysis_fps']),
      frameSize: (j['frame_size'] is List)
          ? (j['frame_size'] as List).map((e) => _toInt(e)).toList()
          : const [],
      timeline: Timeline.fromJson(
        (j['timeline'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      channels: (j['channels'] is List)
          ? (j['channels'] as List)
              .map((e) =>
                  ChannelStat.fromJson((e as Map).cast<String, dynamic>()))
              .toList()
          : const [],
      highlights: (j['highlights'] is List)
          ? (j['highlights'] as List)
              .map((e) =>
                  Highlight.fromJson((e as Map).cast<String, dynamic>()))
              .toList()
          : const [],
      params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      miMatrix: mi,
    );
  }
}

/// 작업 상태 — JobStatus.
class JobStatus {
  final String jobId;
  final String status; // queued | running | done | error
  final double progress; // 0..1
  final String stage;
  final String message;
  final String? error;
  final AnalysisResult? result;

  const JobStatus({
    required this.jobId,
    required this.status,
    required this.progress,
    required this.stage,
    required this.message,
    this.error,
    this.result,
  });

  bool get isDone => status == 'done';
  bool get isError => status == 'error';
  bool get isTerminal => isDone || isError;

  factory JobStatus.fromJson(Map<String, dynamic> j) => JobStatus(
        jobId: (j['job_id'] ?? '').toString(),
        status: (j['status'] ?? 'queued').toString(),
        progress: _toDouble(j['progress']),
        stage: (j['stage'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
        error: j['error'] as String?,
        result: (j['result'] is Map)
            ? AnalysisResult.fromJson(
                (j['result'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// /health 응답.
class HealthInfo {
  final String status;
  final String? python;
  final String? opencv;
  final String? librosa;
  final String? torch;
  final bool cuda;
  final String? device;

  const HealthInfo({
    required this.status,
    this.python,
    this.opencv,
    this.librosa,
    this.torch,
    this.cuda = false,
    this.device,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        status: (j['status'] ?? '').toString(),
        python: j['python'] as String?,
        opencv: j['opencv'] as String?,
        librosa: j['librosa'] as String?,
        torch: j['torch'] as String?,
        cuda: j['cuda'] == true,
        device: j['device'] as String?,
      );
}

/// 분석 파라미터 폼 값 (AnalysisParams 의 일부).
class AnalysisParams {
  final double analysisFps;
  final int topK;
  final double minGapSec;
  final double peakZ;
  final double minClipSec;
  final double maxClipSec;
  final double clipPadSec;
  final bool reencodeClips;

  const AnalysisParams({
    this.analysisFps = 3.0,
    this.topK = 12,
    this.minGapSec = 8.0,
    this.peakZ = 1.2,
    this.minClipSec = 12.0,
    this.maxClipSec = 30.0,
    this.clipPadSec = 4.0,
    this.reencodeClips = true,
  });

  Map<String, dynamic> toJson() => {
        'analysis_fps': analysisFps,
        'top_k': topK,
        'min_gap_sec': minGapSec,
        'peak_z': peakZ,
        'min_clip_sec': minClipSec,
        'max_clip_sec': maxClipSec,
        'clip_pad_sec': clipPadSec,
        'reencode_clips': reencodeClips,
      };
}

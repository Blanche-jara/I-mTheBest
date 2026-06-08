import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// REST + WebSocket 클라이언트.
class ApiClient {
  ApiClient(this.baseUrl);

  /// 예: http://127.0.0.1:8000
  String baseUrl;

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// ws:// (또는 wss://) base 로 변환.
  String get _wsBase {
    final b = _base;
    if (b.startsWith('https://')) return 'wss://${b.substring(8)}';
    if (b.startsWith('http://')) return 'ws://${b.substring(7)}';
    return b;
  }

  Map<String, dynamic> _decode(http.Response r) {
    final body = utf8.decode(r.bodyBytes);
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (decoded as Map).cast<String, dynamic>();
  }

  String _detail(http.Response r) {
    try {
      final m = _decode(r);
      final d = m['detail'];
      if (d != null) return d.toString();
    } catch (_) {}
    return 'HTTP ${r.statusCode}';
  }

  /// GET /health
  Future<HealthInfo> health({Duration timeout = const Duration(seconds: 6)}) async {
    final r = await http.get(_uri('/health')).timeout(timeout);
    if (r.statusCode != 200) {
      throw ApiException(_detail(r), statusCode: r.statusCode);
    }
    return HealthInfo.fromJson(_decode(r));
  }

  /// POST /analyze -> job_id
  Future<String> analyze(String videoPath, AnalysisParams params) async {
    final r = await http
        .post(
          _uri('/analyze'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'video_path': videoPath,
            'params': params.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw ApiException(_detail(r), statusCode: r.statusCode);
    }
    final m = _decode(r);
    final id = m['job_id'];
    if (id == null) {
      throw ApiException('서버가 job_id 를 반환하지 않았습니다');
    }
    return id.toString();
  }

  /// GET /jobs/{id}
  Future<JobStatus> jobStatus(String jobId) async {
    final r = await http
        .get(_uri('/jobs/$jobId'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw ApiException(_detail(r), statusCode: r.statusCode);
    }
    return JobStatus.fromJson(_decode(r));
  }

  /// GET /jobs/{id}/result
  Future<AnalysisResult> jobResult(String jobId) async {
    final r = await http
        .get(_uri('/jobs/$jobId/result'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw ApiException(_detail(r), statusCode: r.statusCode);
    }
    return AnalysisResult.fromJson(_decode(r));
  }

  /// WS /ws/{id} 진행 스트림. done/error 까지 JobStatus 형태로 흘려보낸다.
  /// 연결 자체가 실패하면 예외를 던진다(폴백 폴링 트리거).
  Stream<JobStatus> watch(String jobId) async* {
    final socket = await WebSocket.connect('$_wsBase/ws/$jobId')
        .timeout(const Duration(seconds: 5));
    try {
      await for (final raw in socket) {
        if (raw is! String) continue;
        final dynamic decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final map = decoded.cast<String, dynamic>();
        if (map['error'] != null && map['status'] == null) {
          throw ApiException(map['error'].toString());
        }
        final status = JobStatus.fromJson(map);
        yield status;
        if (status.isTerminal) break;
      }
    } finally {
      await socket.close();
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

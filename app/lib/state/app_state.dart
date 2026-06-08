import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/models.dart';

/// 앱 전역 상태 (ChangeNotifier).
class AppState extends ChangeNotifier {
  AppState() : _client = ApiClient(defaultBaseUrl);

  static const String defaultBaseUrl = 'http://127.0.0.1:8000';

  ApiClient _client;
  ApiClient get client => _client;

  // ---- 서버 ----
  String _baseUrl = defaultBaseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    _baseUrl = v.trim();
    _client = ApiClient(_baseUrl);
    notifyListeners();
  }

  HealthInfo? _health;
  HealthInfo? get health => _health;

  bool _checkingHealth = false;
  bool get checkingHealth => _checkingHealth;

  String? _healthError;
  String? get healthError => _healthError;

  Future<void> checkHealth() async {
    _checkingHealth = true;
    _healthError = null;
    notifyListeners();
    try {
      _health = await _client.health();
    } catch (e) {
      _health = null;
      _healthError = e.toString();
    } finally {
      _checkingHealth = false;
      notifyListeners();
    }
  }

  // ---- 영상 선택 ----
  String? _videoPath;
  String? get videoPath => _videoPath;
  String? get videoFileName {
    final p = _videoPath;
    if (p == null) return null;
    final norm = p.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  void setVideoPath(String? path) {
    _videoPath = path;
    notifyListeners();
  }

  // ---- 파라미터 폼 ----
  AnalysisParams _params = const AnalysisParams();
  AnalysisParams get params => _params;
  void setParams(AnalysisParams p) {
    _params = p;
    notifyListeners();
  }

  // ---- 현재 작업 / 결과 ----
  String? _jobId;
  String? get jobId => _jobId;

  AnalysisResult? _result;
  AnalysisResult? get result => _result;

  void setResult(AnalysisResult r) {
    _result = r;
    notifyListeners();
  }

  /// POST /analyze 후 job_id 반환.
  Future<String> startAnalysis() async {
    final path = _videoPath;
    if (path == null) {
      throw ApiException('먼저 영상을 선택하세요');
    }
    final id = await _client.analyze(path, _params);
    _jobId = id;
    _result = null;
    notifyListeners();
    return id;
  }

  void reset() {
    _jobId = null;
    _result = null;
    notifyListeners();
  }
}

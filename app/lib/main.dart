import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const HighlightStudioApp());
}

class HighlightStudioApp extends StatefulWidget {
  const HighlightStudioApp({super.key});

  @override
  State<HighlightStudioApp> createState() => _HighlightStudioAppState();
}

class _HighlightStudioAppState extends State<HighlightStudioApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '하이라이트 스튜디오',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeScreen(state: _state),
    );
  }
}

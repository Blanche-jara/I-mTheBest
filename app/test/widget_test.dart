// 기본 스모크 테스트 — 홈 화면이 렌더되는지 확인.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:highlight_studio/screens/home_screen.dart';
import 'package:highlight_studio/state/app_state.dart';
import 'package:highlight_studio/theme.dart';

void main() {
  testWidgets('홈 화면 스모크 테스트', (WidgetTester tester) async {
    final state = AppState();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomeScreen(state: state),
      ),
    );

    // 주요 버튼/제목이 표시되는지 확인.
    expect(find.text('분석 시작'), findsOneWidget);
    expect(find.text('영상 선택'), findsOneWidget);
    expect(find.text('서버 연결확인'), findsOneWidget);

    state.dispose();
  });
}

// 채널 PILL 호버 툴팁 + 클릭 도출 팝업 동작 검증.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:highlight_studio/theme.dart';
import 'package:highlight_studio/widgets/channel_info.dart';
import 'package:highlight_studio/widgets/contribution_bar.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('모든 표준 채널 + fused 에 설명 데이터가 존재한다', () {
    for (final ch in [...kChannels, 'fused']) {
      final info = kChannelInfo[ch];
      expect(info, isNotNull, reason: '$ch 설명 누락');
      expect(info!.tldr, isNotEmpty);
      expect(info.what, isNotEmpty);
      expect(info.how, isNotEmpty);
      expect(info.formula, isNotEmpty);
      expect(info.highMeans, isNotEmpty);
    }
  });

  testWidgets('채널 라벨에 의미(tldr) 호버 툴팁이 달린다', (tester) async {
    await tester.pumpWidget(
      _host(const ChannelInfoLabel(channel: 'cheer', text: '환호성')),
    );

    final tip = kChannelInfo['cheer']!.tldr;
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == tip),
      findsOneWidget,
    );
  });

  testWidgets('채널 라벨 클릭 시 도출 팝업이 뜬다 (환호성: 수식·주의·그룹)',
      (tester) async {
    await tester.pumpWidget(
      _host(const ChannelInfoLabel(channel: 'cheer', text: '환호성')),
    );

    await tester.tap(find.byType(ChannelInfoLabel));
    await tester.pumpAndSettle();

    // 다이얼로그 골격
    expect(find.text('무엇을 측정하나요'), findsOneWidget);
    expect(find.text('어떻게 계산하나요'), findsOneWidget);
    expect(find.text('값이 높을수록'), findsOneWidget);
    // 그룹 배지(오디오)
    expect(find.text('오디오'), findsOneWidget);
    // 수식 본문
    expect(find.textContaining('band_ratio'), findsOneWidget);
    // 휴리스틱 주의 박스
    expect(find.textContaining('휴리스틱'), findsWidgets);

    // 닫기 동작
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('어떻게 계산하나요'), findsNothing);
  });

  testWidgets('주의가 없는 채널(음량 변화)은 경고 박스 없이 수식만 보인다',
      (tester) async {
    await tester.pumpWidget(
      _host(const ChannelInfoLabel(channel: 'loudness', text: '음량 변화')),
    );

    await tester.tap(find.byType(ChannelInfoLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('20·log₁₀'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('ContributionBar 안의 채널 라벨도 클릭하면 팝업이 뜬다',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 420,
          child: ContributionBar(contributions: {
            'frame_entropy': 0.4,
            'motion': 0.9,
            'spectral': 1.4,
            'cheer': 7.1,
            'loudness': 2.6,
          }),
        ),
      ),
    );

    final motionLabel = find.byWidgetPredicate(
      (w) => w is ChannelInfoLabel && w.channel == 'motion',
    );
    expect(motionLabel, findsOneWidget);

    await tester.tap(motionLabel);
    await tester.pumpAndSettle();

    // 모션 채널 다이얼로그 제목 + 영상 그룹 배지
    expect(find.text('모션 엔트로피'), findsWidgets);
    expect(find.text('영상'), findsOneWidget);
    expect(find.textContaining('optical flow'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';

import '../theme.dart';

/// 채널별 "의미(호버 툴팁)" + "도출 방식(클릭 팝업)" 설명 데이터.
///
/// 내용은 engine 구현(`engine/video_channel.py`, `engine/audio_channel.py`,
/// `engine/infotheory.py`, `engine/fusion.py`)과 docs/03-explainability.md 에
/// 정확히 대응한다. 모든 채널은 raw 특징을 뽑은 뒤 running_surprise(−log₂ p̂)를
/// 거쳐 동일한 bits 단위의 surprise 가 된다.
class ChannelInfo {
  const ChannelInfo({
    required this.group,
    required this.tldr,
    required this.what,
    required this.how,
    required this.formula,
    required this.highMeans,
    this.caveat,
  });

  /// 'video' | 'audio' | 'fused'.
  final String group;

  /// 한 줄 의미 — 마우스 호버 시 노출.
  final String tldr;

  /// "무엇을 측정하나요" 본문.
  final String what;

  /// "어떻게 계산하나요" 단계.
  final List<String> how;

  /// 핵심 수식.
  final String formula;

  /// "값이 높을수록"의 의미.
  final String highMeans;

  /// 주의사항(있으면 경고 박스로 노출). 환호성처럼 휴리스틱인 채널에 사용.
  final String? caveat;
}

const String _surpriseNote =
    '모든 채널은 raw 특징을 뽑은 뒤 running_surprise(−log₂ p̂)를 거쳐 동일한 bits '
    '단위의 surprise 가 됩니다. 최종 신호 fused 는 채널들을 최대엔트로피 가중'
    '(1−평균NMI)·liveness 으로 합쳐 만듭니다.';

/// 채널 식별자 -> 설명. theme.dart 의 channelLabelsKo / AppColors.channel 와 짝.
const Map<String, ChannelInfo> kChannelInfo = {
  'frame_entropy': ChannelInfo(
    group: 'video',
    tldr: '한 프레임 화면의 공간 복잡도. 화면이 복잡·혼란스러울수록 높습니다.',
    what:
        '한 장의 프레임이 시각적으로 얼마나 복잡한지를 봅니다. 로딩 화면처럼 단조로우면 '
        '낮고, 교전·폭발처럼 디테일이 많으면 높습니다.',
    how: [
      '프레임을 그레이스케일로 변환하고 분석 해상도로 축소합니다.',
      '256단계 픽셀 강도 히스토그램으로 분포 p 를 만듭니다.',
      'Shannon 엔트로피 H = −Σ p·log₂p (0~8 bits) 를 그 프레임의 raw 값으로 씁니다.',
      'raw 시계열을 running_surprise 로 통과시켜 최근 분포 대비 급변을 bits 로 환산합니다.',
    ],
    formula: 'H(frame) = −Σ p(i)·log₂ p(i)\nsurprise = −log₂ p̂(현재값)',
    highMeans: '직전 구간 대비 화면 복잡도가 급변한 순간 (장면 전환·갑작스러운 시각적 혼잡).',
  ),
  'motion': ChannelInfo(
    group: 'video',
    tldr: '화면 움직임의 크기와 무질서도. 혼란스러운 교전일수록 높습니다.',
    what:
        '연속한 두 프레임 사이의 움직임이 얼마나 크고 산만한지를 봅니다. 정지 화면이나 '
        '단조로운 카메라 팬은 낮고, 사방에서 움직이는 교전 장면은 높습니다.',
    how: [
      '연속 프레임 간 dense optical flow(Farneback)로 픽셀별 움직임 벡터를 구합니다.',
      '움직임 크기(magnitude) 분포의 엔트로피를 계산합니다(여러 방향·세기로 흩어질수록 큼).',
      '평균 크기의 tanh 를 곱해 완전 정지 구간을 0 근처로 누릅니다.',
      'running_surprise 로 최근 대비 급변을 bits 로 환산합니다.',
    ],
    formula: 'motion = H(|flow|) · tanh(mean|flow|)\nsurprise = −log₂ p̂',
    highMeans: '갑자기 움직임이 폭발하거나 패턴이 무너진 순간 (난전·빠른 이동).',
  ),
  'spectral': ChannelInfo(
    group: 'audio',
    tldr: '소리의 주파수 구성이 갑자기 바뀌는 정도(onset). 새 소리·타격음에 반응합니다.',
    what:
        '오디오 스펙트럼이 시간에 따라 얼마나 급격히 변하는지(novelty)를 봅니다. 새로운 '
        '소리가 등장하거나 음색이 바뀌는 순간을 잡습니다.',
    how: [
      'ffmpeg 로 모노 PCM 을 스트리밍하고 STFT 스펙트로그램을 만듭니다.',
      '스펙트럼을 dB 로 변환한 뒤 librosa onset_strength(spectral novelty)를 계산합니다.',
      'running_surprise 로 최근 분포 대비 급변을 bits 로 환산합니다.',
    ],
    formula: 'spectral = onset_strength(STFT_dB)\nsurprise = −log₂ p̂',
    highMeans: '새로운 소리가 갑자기 등장한 순간 (타격·효과음·컷 전환음).',
  ),
  'cheer': ChannelInfo(
    group: 'audio',
    tldr: '군중 함성·환호의 가능성(휴리스틱). 중역대 광대역·평탄 잡음성 소리에 반응합니다.',
    what:
        '관중의 함성/환호처럼 들리는 소리를 추정합니다. 함성은 1~6kHz 중역대 에너지가 크고 '
        '스펙트럼이 평탄(광대역 잡음성)하다는 특성을 이용합니다.',
    how: [
      'STFT 스펙트럼에서 1~6kHz 대역 에너지 비율을 구합니다.',
      '스펙트럼 평탄도 = 기하평균/산술평균 (0=순음, 1=백색잡음) 을 곱합니다.',
      '대역 에너지의 log1p 를 추가로 곱해 raw 점수를 만듭니다.',
      'running_surprise 로 함성이 솟구치는 onset 을 bits 로 잡습니다.',
    ],
    formula: 'cheer = band_ratio(1–6kHz) · flatness · log(1+band_energy)',
    highMeans: '군중 함성이 솟구친 순간 (득점·결정적 장면 직후의 환호).',
    caveat:
        '현재는 규칙 기반 휴리스틱이라 바람·관중석 잡음·일부 효과음을 함성으로 오인할 수 '
        '있습니다. torch 가용 시 학습형 분류기로 대체하도록 설계되어 있습니다.',
  ),
  'loudness': ChannelInfo(
    group: 'audio',
    tldr: '음량(dB)의 급변. 갑작스럽게 커지는 소리에 반응합니다.',
    what:
        '전체 음량이 얼마나 갑자기 변하는지를 봅니다. 절대 음량이 아니라 "최근 음량 분포 '
        '대비 급변"을 점수로 씁니다.',
    how: [
      'STFT 로부터 프레임별 RMS 에너지를 구합니다.',
      '데시벨로 변환합니다: dB = 20·log₁₀(rms).',
      'running_surprise 로 최근 음량 분포에서 현재 값이 얼마나 드문지를 bits 로 환산합니다.',
    ],
    formula: 'loudness = 20·log₁₀(RMS)\nsurprise = −log₂ p̂',
    highMeans: '음량이 갑자기 치솟거나 꺼진 순간 (폭발·정적 후 굉음).',
  ),
  'fused': ChannelInfo(
    group: 'fused',
    tldr: '5개 채널을 합친 "이 순간의 총 놀라움". 하이라이트 점수의 바탕입니다.',
    what:
        '영상·오디오 5개 채널의 surprise 를 가중 합산한 최종 신호입니다. 이 곡선의 피크가 '
        '하이라이트 후보가 되고, 구간 적분값이 점수(total_bits)가 됩니다.',
    how: [
      '각 채널 surprise sᵢ(t) 를 같은 bits 단위로 맞춥니다.',
      '채널 간 중복(NMI)이 크면 가중치를 낮춥니다: wᵢ ∝ (1−평균NMI)·liveness.',
      'fused(t) = Σ wᵢ·sᵢ(t) 로 합칩니다.',
      '적응형 임계값(mean+peak_z·std)으로 피크를 찾고, 구간을 확장해 ∫fused dt 를 점수로 씁니다.',
    ],
    formula: 'fused(t) = Σ wᵢ · sᵢ(t)\nscore = ∫ fused(t) dt',
    highMeans: '여러 채널이 동시에 놀란 순간 = 강력한 하이라이트 후보.',
  ),
};

String _groupLabel(String group) {
  switch (group) {
    case 'video':
      return '영상';
    case 'audio':
      return '오디오';
    case 'fused':
      return '융합';
    default:
      return group;
  }
}

/// 채널 도출 방식 설명 다이얼로그를 띄운다. 등록되지 않은 채널은 무시.
void showChannelInfoDialog(BuildContext context, String channel) {
  final info = kChannelInfo[channel];
  if (info == null) return;
  showDialog<void>(
    context: context,
    builder: (_) => _ChannelInfoDialog(channel: channel, info: info),
  );
}

/// 채널명 라벨을 감싸 호버 툴팁(의미) + 탭(도출 팝업)을 부여하는 위젯.
/// 기여 막대·가중치 막대처럼 라벨이 텍스트로 노출되는 곳에 사용.
class ChannelInfoLabel extends StatelessWidget {
  const ChannelInfoLabel({
    super.key,
    required this.channel,
    required this.text,
    this.style,
    this.showIcon = true,
  });

  final String channel;
  final String text;
  final TextStyle? style;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final info = kChannelInfo[channel];
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
        if (showIcon && info != null) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.info_outline,
            size: 11,
            color: AppColors.textSecondary.withValues(alpha: 0.65),
          ),
        ],
      ],
    );
    if (info == null) return label;
    return channelTooltip(
      channel,
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showChannelInfoDialog(context, channel),
          child: label,
        ),
      ),
    );
  }
}

/// 채널 의미(tldr)를 호버 툴팁으로 덧입힌다. 등록되지 않은 채널은 child 그대로.
Widget channelTooltip(String channel, Widget child) {
  final info = kChannelInfo[channel];
  if (info == null) return child;
  return Tooltip(
    message: info.tldr,
    waitDuration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    textStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 11.5,
      height: 1.35,
    ),
    child: child,
  );
}

/// 채널 색 점 + 라벨 + 그룹 배지 + 도출 단계/수식을 보여주는 다이얼로그.
class _ChannelInfoDialog extends StatelessWidget {
  const _ChannelInfoDialog({required this.channel, required this.info});

  final String channel;
  final ChannelInfo info;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forChannel(channel);
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              channelLabel(channel),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _GroupBadge(color: color, text: _groupLabel(info.group)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SectionHeader('무엇을 측정하나요'),
              _Body(info.what),
              const SizedBox(height: 16),
              const _SectionHeader('어떻게 계산하나요'),
              const SizedBox(height: 6),
              for (var i = 0; i < info.how.length; i++)
                _Step(index: i + 1, text: info.how[i], color: color),
              const SizedBox(height: 12),
              _FormulaBox(info.formula),
              const SizedBox(height: 16),
              const _SectionHeader('값이 높을수록'),
              _Body(info.highMeans),
              if (info.caveat != null) ...[
                const SizedBox(height: 14),
                _CaveatBox(info.caveat!),
              ],
              const SizedBox(height: 16),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 12),
              Text(
                _surpriseNote,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _GroupBadge extends StatelessWidget {
  const _GroupBadge({required this.color, required this.text});
  final Color color;
  final String text;

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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        height: 1.5,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, required this.color});
  final int index;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormulaBox extends StatelessWidget {
  const _FormulaBox(this.formula);
  final String formula;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        formula,
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12.5,
          height: 1.5,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _CaveatBox extends StatelessWidget {
  const _CaveatBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

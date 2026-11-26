import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/translation/photo_paragraphs.dart';
import '../../../models/translation/photo_translation_result.dart';
import '../../../providers/translation/photo_translation_state.dart';
import '../../../services/photo_normalizer.dart';
import '../translation_box_overlay.dart';
import 'fake_translation_banner.dart';
import 'paragraph_detail_sheet.dart';

part 'photo_result_panels.dart';

/// 결과 화면은 사진을 보여 주는 화면이라 앱 테마(라이트/다크)와 상관없이 어두운 테마로 그린다.
/// 상세 시트처럼 사진을 덮지 않는 화면은 앱 테마를 따른다.
final ThemeData _photoViewTheme = AppTheme.darkTheme;

/// 사진 번역 결과 화면: 기준 사진 전체(contain) 위에 번역 상자를 덮어 그린다.
///
/// 사진과 상자는 한 [InteractiveViewer] 안의 같은 `Stack`에 있어 확대·이동을 함께 한다. 상자 좌표는
/// 기준 사진 좌표에 맞춘 배율(`min(보기 폭 / 사진 폭, 보기 높이 / 사진 높이)`)을 한 번만 곱한다.
class PhotoResultView extends StatefulWidget {
  const PhotoResultView({
    super.key,
    required this.state,
    required this.onRetake,
    required this.onRetry,
    required this.onToggleOriginal,
    this.transformationController,
  });

  final PhotoTranslationState state;
  final VoidCallback onRetake;
  final VoidCallback onRetry;
  final VoidCallback onToggleOriginal;

  /// 확대·이동 상태. 없으면 이 위젯이 만들고 정리한다.
  final TransformationController? transformationController;

  static const String retakeLabel = '재촬영';
  static const String showOriginalLabel = '원문 보기';
  static const String showTranslationLabel = '번역 보기';
  static const String preparingLabel = '사진을 준비하는 중';
  static const String uploadingLabel = '번역하는 중';
  static const String failedTitle = '번역하지 못했어요';
  static const String retryLabel = '다시 시도';
  static const String fallbackNotice = '일부 문단은 글자만으로 번역했어요';
  static const String omittedNotice = '일부만 번역했어요';

  static String missingNotice(int count) => '번역하지 못한 문단 $count개';

  @override
  State<PhotoResultView> createState() => _PhotoResultViewState();
}

/// 상자 목록 입력. 같은 결과·문단·배율이면 같은 목록 객체를 넘겨 다시 배치하지 않게 한다.
typedef _BoxesKey = ({
  PhotoTranslationResult? result,
  List<OcrParagraph> paragraphs,
  double fit,
});

class _PhotoResultViewState extends State<PhotoResultView> {
  TransformationController? _ownController;
  _BoxesKey? _boxesKey;
  List<TranslationBox> _boxes = const [];

  TransformationController get _controller =>
      widget.transformationController ??
      (_ownController ??= TransformationController());

  @override
  void didUpdateWidget(PhotoResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 새 사진이면 확대·이동을 처음으로 되돌린다.
    if (oldWidget.state.photo?.path != widget.state.photo?.path) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  Map<String, TranslatedParagraph> get _translatedById => {
    for (final paragraph
        in widget.state.result?.paragraphs ?? const <TranslatedParagraph>[])
      paragraph.id: paragraph,
  };

  // 응답에 있는 문단만 상자로 만든다. 응답에 없는 문단은 그리지 않는다.
  List<TranslationBox> _boxesFor(double fit) {
    final state = widget.state;
    final key = (result: state.result, paragraphs: state.paragraphs, fit: fit);
    final current = _boxesKey;
    if (current != null &&
        identical(current.result, key.result) &&
        identical(current.paragraphs, key.paragraphs) &&
        current.fit == fit) {
      return _boxes;
    }
    final byId = _translatedById;
    final boxes = <TranslationBox>[];
    for (final paragraph in state.paragraphs) {
      final translated = byId[paragraph.id];
      if (translated == null) {
        continue;
      }
      final box = paragraph.box;
      boxes.add(
        TranslationBox(
          Rect.fromLTRB(
            box.left * fit,
            box.top * fit,
            box.right * fit,
            box.bottom * fit,
          ),
          paragraph.lineCount,
          translated.translated,
          id: paragraph.id,
          uncertain: translated.uncertain,
          fallback: translated.source == PhotoTranslationSource.ocrText,
        ),
      );
    }
    _boxesKey = key;
    _boxes = List<TranslationBox>.unmodifiable(boxes);
    return _boxes;
  }

  void _openDetail(String id) {
    final paragraph = _translatedById[id];
    if (paragraph != null) {
      showParagraphDetailSheet(
        context,
        paragraph,
        simulated: widget.state.result?.simulated ?? false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final completed = state.status == PhotoTranslationStatus.completed;

    // Material: 안쪽 글자·아이콘이 어두운 테마의 기본 글자 색을 쓰게 한다.
    return Theme(
      data: _photoViewTheme,
      child: Material(
        color: _photoViewTheme.colorScheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              onRetake: widget.onRetake,
              showingOriginal: completed ? state.showOriginal : null,
              onToggleOriginal: widget.onToggleOriginal,
            ),
            if (state.result?.simulated ?? false)
              const FakeTranslationBanner(
                message: FakeTranslationBanner.resultMessage,
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    if (state.photo != null) _buildPhoto(state.photo!),
                    ..._buildStatus(constraints),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto(NormalizedPhoto photo) {
    final state = widget.state;
    final showBoxes =
        state.status == PhotoTranslationStatus.completed && !state.showOriginal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final view = constraints.biggest;
        if (photo.width <= 0 || photo.height <= 0 || view.isEmpty) {
          return const SizedBox.shrink();
        }
        final fit = math.min(
          view.width / photo.width,
          view.height / photo.height,
        );
        return InteractiveViewer(
          transformationController: _controller,
          maxScale: 5,
          child: Center(
            child: SizedBox(
              width: photo.width * fit,
              height: photo.height * fit,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(photo.path),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    errorBuilder: (context, _, _) => ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  if (showBoxes)
                    TranslationBoxOverlay(
                      boxes: _boxesFor(fit),
                      onBoxTap: _openDetail,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 진행 표시, 실패 안내, 결과 안내 묶음.
  List<Widget> _buildStatus(BoxConstraints constraints) {
    final state = widget.state;

    switch (state.status) {
      case PhotoTranslationStatus.preparing:
        return const [_Progress(label: PhotoResultView.preparingLabel)];
      case PhotoTranslationStatus.uploading:
        return const [_Progress(label: PhotoResultView.uploadingLabel)];
      case PhotoTranslationStatus.failed:
      case PhotoTranslationStatus.noText:
      case PhotoTranslationStatus.unsupportedPhoto:
        final failed = state.status == PhotoTranslationStatus.failed;
        return [
          _FailurePanel(
            failed: failed,
            message: state.errorMessage,
            // 사진이 있으면 그대로 보이게 아래에 두고, 없으면 가운데에 둔다.
            hasPhoto: state.photo != null,
            // 다시 보내 나아질 수 있는 실패일 때만 다시 시도를 둔다(판단은 Notifier가 한다).
            onRetry: failed && state.canRetry ? widget.onRetry : null,
            onRetake: widget.onRetake,
          ),
        ];
      case PhotoTranslationStatus.completed:
        final notices = _notices();
        if (notices.isEmpty) {
          return const [];
        }
        return [
          _NoticePanel(
            notices: notices,
            maxHeight: constraints.maxHeight * 0.4,
          ),
        ];
      case PhotoTranslationStatus.idle:
      case PhotoTranslationStatus.awaitingConsent:
        return const [];
    }
  }

  List<String> _notices() {
    final state = widget.state;
    final translated =
        state.result?.paragraphs ?? const <TranslatedParagraph>[];
    final byId = _translatedById;
    final missing = state.paragraphs
        .where((paragraph) => !byId.containsKey(paragraph.id))
        .length;
    return [
      if (translated.any((p) => p.source == PhotoTranslationSource.ocrText))
        PhotoResultView.fallbackNotice,
      if (missing > 0) PhotoResultView.missingNotice(missing),
      if (state.omittedCount > 0) PhotoResultView.omittedNotice,
    ];
  }
}

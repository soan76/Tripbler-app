import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/translation/photo_paragraphs.dart';
import '../../../models/translation/photo_translation_result.dart';
import '../../../providers/translation/photo_translation_state.dart';
import '../../../services/photo_normalizer.dart';
import '../translation_box_overlay.dart';
import 'paragraph_detail_sheet.dart';

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
          1,
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
      showParagraphDetailSheet(context, paragraph);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final completed = state.status == PhotoTranslationStatus.completed;

    return ColoredBox(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            onRetake: widget.onRetake,
            toggleLabel: !completed
                ? null
                : state.showOriginal
                ? PhotoResultView.showTranslationLabel
                : PhotoResultView.showOriginalLabel,
            onToggleOriginal: widget.onToggleOriginal,
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
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF303030)),
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

  // 진행 표시, 실패·안내 카드, 결과 안내 줄.
  List<Widget> _buildStatus(BoxConstraints constraints) {
    final state = widget.state;
    final maxNoticeHeight = constraints.maxHeight * 0.4;

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
          _MessageCard(
            title: failed ? PhotoResultView.failedTitle : null,
            message: state.errorMessage,
            // 사진이 없으면(정리·글자 인식 실패) 다시 보낼 것이 없으므로 재촬영만 둔다.
            onRetry: failed && state.photo != null ? widget.onRetry : null,
          ),
        ];
      case PhotoTranslationStatus.completed:
        final notices = _notices();
        if (notices.isEmpty) {
          return const [];
        }
        return [
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxNoticeHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final notice in notices) _Notice(notice)],
                ),
              ),
            ),
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onRetake,
    required this.toggleLabel,
    required this.onToggleOriginal,
  });

  final VoidCallback onRetake;
  final String? toggleLabel;
  final VoidCallback onToggleOriginal;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(foregroundColor: Colors.white);
    final label = toggleLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Flexible(
            child: TextButton.icon(
              style: style,
              onPressed: onRetake,
              icon: const Icon(Icons.arrow_back),
              label: const Text(PhotoResultView.retakeLabel),
            ),
          ),
          const Spacer(),
          if (label != null)
            Flexible(
              child: TextButton(
                style: style,
                onPressed: onToggleOriginal,
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black38,
      child: Center(
        child: _Card(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    final message = this.message;
    final onRetry = this.onRetry;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text(PhotoResultView.retryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _Card(
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

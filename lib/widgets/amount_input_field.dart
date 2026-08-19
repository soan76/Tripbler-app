import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// 금액 입력 필드 위젯
class AmountInputField extends StatefulWidget {
  final double amount;
  final ValueChanged<double> onChanged;
  final VoidCallback? onTap;

  // 기준 통화인지 여부
  final bool isBase;

  const AmountInputField({
    super.key,
    required this.amount,
    required this.onChanged,
    this.onTap,
    this.isBase = false,
  });

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  late final TextEditingController _controller;

  final NumberFormat _formatter = NumberFormat('#,##0.########');

  // 기본 글자 크기
  static const double _defaultFontSize = 22;

  // 너무 길어졌을 때 허용할 최소 글자 크기
  static const double _minimumFontSize = 12;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: _formatter.format(widget.amount));
  }

  @override
  void didUpdateWidget(covariant AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.amount != widget.amount) {
      final newText = _formatter.format(widget.amount);

      if (_controller.text != newText) {
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 기준 통화와 일반 통화에 맞는 텍스트 색상
    final textColor = widget.isBase
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 현재 입력된 숫자 길이와 실제 입력 영역을 이용해
        // 적절한 글자 크기를 계산
        final fontSize = _calculateFontSize(
          text: _controller.text,
          maxWidth: constraints.maxWidth,
          textColor: textColor,
        );

        return TextField(
          controller: _controller,

          onTap: widget.onTap,

          textAlign: TextAlign.right,

          keyboardType: const TextInputType.numberWithOptions(decimal: true),

          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            _ThousandsSeparatorInputFormatter(),
          ],

          // TextField 자체의 별도 배경 제거
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,

            filled: false,

            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),

          // 입력 영역에 맞게 자동 계산된 글자 크기 사용
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),

          cursorColor: colorScheme.primary,

          onChanged: (value) {
            // 입력 문자열 길이가 변경될 때
            // 글자 크기를 다시 계산하기 위해 rebuild
            setState(() {});

            final rawValue = value.replaceAll(',', '');
            final parsed = double.tryParse(rawValue) ?? 0;

            widget.onChanged(parsed);
          },
        );
      },
    );
  }

  // 현재 입력된 텍스트가 입력 영역을 넘지 않도록
  // 적절한 글자 크기를 계산
  double _calculateFontSize({
    required String text,
    required double maxWidth,
    required Color textColor,
  }) {
    if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
      return _defaultFontSize;
    }

    double fontSize = _defaultFontSize;

    while (fontSize > _minimumFontSize) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        maxLines: 1,
        textDirection: ui.TextDirection.ltr,
      )..layout();

      if (textPainter.width <= maxWidth) {
        return fontSize;
      }

      fontSize -= 1;
    }

    return _minimumFontSize;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// 입력값에 천 단위 구분자를 적용하는 TextInputFormatter
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,##0.########');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    final rawText = text.replaceAll(',', '');

    if (rawText == '.') {
      return oldValue;
    }

    if ('.'.allMatches(rawText).length > 1) {
      return oldValue;
    }

    final parts = rawText.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : null;

    final integerNumber = int.tryParse(integerPart.isEmpty ? '0' : integerPart);

    if (integerNumber == null) {
      return oldValue;
    }

    String formatted = _formatter.format(integerNumber);

    if (decimalPart != null) {
      formatted = '$formatted.$decimalPart';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

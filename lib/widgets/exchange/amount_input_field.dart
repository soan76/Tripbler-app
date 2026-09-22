import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// 금액 입력 필드 위젯
class AmountInputField extends StatefulWidget {
  final double amount;
  final ValueChanged<double> onChanged;

  // 금액 입력 영역을 터치했을 때 호출
  final VoidCallback? onTap;

  // 현재 선택된 통화 행인지 여부
  final bool isBase;

  // -1 = 자동
  // 0~6 = 최대 소수점 자릿수
  final int decimalPlaces;

  const AmountInputField({
    super.key,
    required this.amount,
    required this.onChanged,
    required this.decimalPlaces,
    this.onTap,
    this.isBase = false,
  });

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  late final TextEditingController _controller;

  // 기본 글자 크기
  static const double _defaultFontSize = 22;

  // 숫자가 길어졌을 때 줄일 수 있는 최소 글자 크기
  static const double _minimumFontSize = 12;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: _formatAmount(widget.amount));
  }

  @override
  void didUpdateWidget(covariant AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 금액 또는 자릿수 설정이 바뀌면 표시값도 갱신
    if (oldWidget.amount != widget.amount ||
        oldWidget.decimalPlaces != widget.decimalPlaces) {
      final newText = _formatAmount(widget.amount);

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

    // 선택된 통화 행과 일반 통화 행의 글자색 구분
    final textColor = widget.isBase
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 현재 입력값이 영역을 넘지 않도록
        // 실제 텍스트 너비를 기준으로 글자 크기 계산
        final fontSize = _calculateFontSize(
          text: _controller.text,
          maxWidth: constraints.maxWidth,
          textColor: textColor,
        );

        return TextField(
          controller: _controller,

          // 터치 즉시 해당 통화를 선택 상태로 변경
          onTap: widget.onTap,

          textAlign: TextAlign.right,

          keyboardType: const TextInputType.numberWithOptions(decimal: true),

          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),

            _ThousandsSeparatorInputFormatter(
              decimalPlaces: widget.decimalPlaces,
            ),
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

          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),

          cursorColor: colorScheme.primary,

          onChanged: (value) {
            // 입력 길이가 변경될 때 글자 크기 재계산
            setState(() {});

            final rawValue = value.replaceAll(',', '');

            final parsed = double.tryParse(rawValue) ?? 0;

            widget.onChanged(parsed);
          },
        );
      },
    );
  }

  // 현재 설정된 자릿수 제한에 맞게 금액 문자열 생성
  String _formatAmount(double amount) {
    // 자동
    if (widget.decimalPlaces == -1) {
      return NumberFormat('#,##0.########').format(amount);
    }

    // 소수점 없음
    if (widget.decimalPlaces == 0) {
      return NumberFormat('#,##0').format(amount);
    }

    // 최대 소수점 자릿수
    final decimalPattern = '#' * widget.decimalPlaces;

    return NumberFormat('#,##0.$decimalPattern').format(amount);
  }

  // 입력 영역을 넘어가지 않도록 적절한 글자 크기 계산
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

// 입력값에 천 단위 구분자를 적용하고
// 설정된 소수점 자릿수만큼 입력을 제한하는 formatter
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final int decimalPlaces;

  _ThousandsSeparatorInputFormatter({required this.decimalPlaces});

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

    // "."만 입력되는 경우 방지
    if (rawText == '.') {
      return oldValue;
    }

    // 소수점 두 개 이상 입력 방지
    if ('.'.allMatches(rawText).length > 1) {
      return oldValue;
    }

    final parts = rawText.split('.');

    final integerPart = parts[0];

    final decimalPart = parts.length > 1 ? parts[1] : null;

    // 자릿수 제한이 0이면 소수점 입력 자체를 막음
    if (decimalPlaces == 0 && decimalPart != null) {
      return oldValue;
    }

    // 자동(-1)이 아닌 경우
    // 설정된 소수점 자릿수를 초과하지 못하도록 제한
    if (decimalPlaces >= 0 &&
        decimalPart != null &&
        decimalPart.length > decimalPlaces) {
      return oldValue;
    }

    final integerNumber = int.tryParse(integerPart.isEmpty ? '0' : integerPart);

    if (integerNumber == null) {
      return oldValue;
    }

    final formattedInteger = NumberFormat('#,##0').format(integerNumber);

    String formatted = formattedInteger;

    // 사용자가 소수점을 입력한 상태 유지
    if (decimalPart != null) {
      formatted = '$formatted.$decimalPart';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

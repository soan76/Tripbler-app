import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AmountInputField extends StatefulWidget {
  final double amount;
  final ValueChanged<double> onChanged;

  const AmountInputField({
    super.key,
    required this.amount,
    required this.onChanged,
  });

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  late final TextEditingController _controller;
  final NumberFormat _formatter = NumberFormat('#,##0.########');

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
        _controller.text = newText;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        _ThousandsSeparatorInputFormatter(),
      ],
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
      ),
      onChanged: (value) {
        final rawValue = value.replaceAll(',', '');
        final parsed = double.tryParse(rawValue) ?? 0;
        widget.onChanged(parsed);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

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

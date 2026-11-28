import 'dart:ui';

import '../../domain/duty_free/receipt_parser.dart';
import '../../domain/translation/text_paragraphs.dart';
import '../ocr_service.dart';

/// 영수증 사진의 글자를 기기에서 읽어(ML Kit) [ParsedReceipt]로 만든다. 사진은 서버로 보내지 않고,
/// 읽은 글자도 로그에 남기지 않는다.
class ReceiptScanService {
  ReceiptScanService(this._ocr, {ReceiptParser parser = const ReceiptParser()})
    : _parser = parser;

  final OcrService _ocr;
  final ReceiptParser _parser;

  Future<ParsedReceipt> scan(String imagePath) async {
    final lines = await _ocr.recognizeTextLines(
      imagePath: imagePath,
      sourceLanguageCode: 'auto',
    );
    return _parser.parse(joinRows(lines));
  }

  /// 영수증은 상품명과 금액이 다른 글자 덩어리로 읽히므로, 같은 높이의 줄을 왼쪽부터 이어
  /// 한 줄로 만든다(위에서 아래 순서).
  static List<String> joinRows(List<RecognizedTextLine> lines) {
    final sorted = [...lines]
      ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
    final rows = <List<RecognizedTextLine>>[];
    for (final line in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null && _sameRow(row.first.box, line.box)) {
        row.add(line);
      } else {
        rows.add([line]);
      }
    }
    return [
      for (final row in rows)
        (row..sort((a, b) => a.box.left.compareTo(b.box.left)))
            .map((l) => l.text.trim())
            .where((t) => t.isNotEmpty)
            .join(' '),
    ];
  }

  static bool _sameRow(Rect a, Rect b) {
    final height = a.height < b.height ? a.height : b.height;
    return (a.center.dy - b.center.dy).abs() <= height / 2;
  }
}

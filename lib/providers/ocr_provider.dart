import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../services/ocr_service.dart';

/// 기기 안에서 글자를 인식하는 서비스. 번역과 면세 영수증 읽기가 함께 쓴다.
final ocrServiceProvider = Provider<OcrService>((ref) => OcrService());

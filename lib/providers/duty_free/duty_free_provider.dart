import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/duty_free/duty_free_calculator.dart';
import '../../models/duty_free/duty_free_item.dart';
import '../../models/duty_free/duty_free_rules.dart';
import '../../services/duty_free/duty_free_rules_service.dart';
import '../../services/duty_free/duty_free_storage_service.dart';
import '../../services/duty_free/receipt_scan_service.dart';
import '../ocr_provider.dart';

/// 면세 규칙 Service. 지금은 앱 안의 예시 값을 준다. 테스트에서 바꾼다.
final dutyFreeRulesServiceProvider = Provider<DutyFreeRulesService>(
  (_) => const DutyFreeRulesService(),
);

/// 산 물건 저장소. 테스트에서 바꾼다.
final dutyFreeStorageServiceProvider = Provider<DutyFreeStorageService>(
  (_) => DutyFreeStorageService(),
);

/// 면세 화면이 쓰는 현재 시각. 테스트에서 바꾼다.
final dutyFreeClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// 면세 규칙. 받지 못하면 오류이고, 다시 시도는 `ref.invalidate`로 한다.
final dutyFreeRulesProvider = FutureProvider<DutyFreeRules>(
  (ref) => ref.watch(dutyFreeRulesServiceProvider).fetch(),
);

enum DutyFreeLoadStatus { loading, ready, failed }

class DutyFreeState {
  const DutyFreeState({
    this.status = DutyFreeLoadStatus.loading,
    this.trip = DutyFreeTrip.empty,
  });

  final DutyFreeLoadStatus status;
  final DutyFreeTrip trip;

  bool get isReady => status == DutyFreeLoadStatus.ready;
  bool get adult => trip.adult;
  List<DutyFreeItem> get items => trip.items;
}

/// 산 물건 목록·나이·추가한 영수증을 불러오고 바꿀 때마다 저장한다.
///
/// 바꾸는 일은 하나씩 차례로 저장한다. 저장에 실패하면 예외를 던지고 상태는 그대로 둔다.
/// 불러오기 전이나 실패한 상태에서는 [StateError](저장된 기록을 덮어쓰지 않게).
class DutyFreeNotifier extends Notifier<DutyFreeState> {
  late DutyFreeStorageService _storage;
  late DateTime Function() _now;
  int _loadId = 0;
  int _idSeq = 0;
  Future<void> _queue = Future.value();

  @override
  DutyFreeState build() {
    _storage = ref.read(dutyFreeStorageServiceProvider);
    _now = ref.read(dutyFreeClockProvider);
    _load();
    return const DutyFreeState();
  }

  Future<void> retry() {
    if (state.status != DutyFreeLoadStatus.failed) return Future.value();
    state = const DutyFreeState();
    return _load();
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    try {
      final trip = await _storage.load();
      if (!ref.mounted || loadId != _loadId) return;
      state = DutyFreeState(status: DutyFreeLoadStatus.ready, trip: trip);
    } catch (_) {
      if (!ref.mounted || loadId != _loadId) return;
      state = const DutyFreeState(status: DutyFreeLoadStatus.failed);
    }
  }

  /// 새 물건 id.
  String newId() => 'df-${_now().microsecondsSinceEpoch}-${_idSeq++}';

  DateTime now() => _now();

  Future<void> setAdult(bool adult) => _change((t) => t.copyWith(adult: adult));

  Future<void> add(DutyFreeItem item) =>
      _change((t) => t.copyWith(items: [...t.items, item]));

  /// 같은 id의 물건을 바꾼다. 없으면 [StateError].
  Future<void> update(DutyFreeItem item) => _change((t) {
    final index = t.items.indexWhere((i) => i.id == item.id);
    if (index < 0) throw StateError('수정할 물건이 없습니다.');
    return t.copyWith(items: [...t.items]..[index] = item);
  });

  /// [id] 물건을 지운다. 없으면 [StateError].
  Future<void> remove(String id) => _change((t) {
    final items = t.items.where((i) => i.id != id).toList();
    if (items.length == t.items.length) throw StateError('삭제할 물건이 없습니다.');
    return t.copyWith(items: items);
  });

  /// 영수증에서 고른 물건을 넣고 영수증 키를 기억한다(중복 경고용).
  Future<void> addReceipt(List<DutyFreeItem> items, String receiptKey) {
    if (items.isEmpty) return Future.value();
    return _change(
      (t) => t.copyWith(
        items: [...t.items, ...items],
        receiptKeys: {...t.receiptKeys, receiptKey},
      ),
    );
  }

  /// 산 물건과 추가한 영수증을 모두 지운다. 나이는 그대로 둔다.
  Future<void> startNewTrip() => _change(
    (t) => DutyFreeTrip(adult: t.adult, items: const [], receiptKeys: const {}),
  );

  Future<void> _change(DutyFreeTrip Function(DutyFreeTrip trip) change) {
    final run = _queue.then((_) async {
      if (!ref.mounted) return;
      if (!state.isReady) {
        throw StateError('면세 기록을 불러오기 전에는 바꿀 수 없습니다.');
      }
      final next = change(state.trip);
      await _storage.save(next);
      if (!ref.mounted) return;
      state = DutyFreeState(
        status: DutyFreeLoadStatus.ready,
        trip: next.copyWith(
          items: List.unmodifiable(next.items),
          receiptKeys: Set.unmodifiable(next.receiptKeys),
        ),
      );
    });
    _queue = run.catchError((_) {});
    return run;
  }
}

final dutyFreeProvider = NotifierProvider<DutyFreeNotifier, DutyFreeState>(
  DutyFreeNotifier.new,
);

/// 산 물건과 규칙으로 계산한 요약. 규칙이 없거나 기록을 불러오기 전이면 null.
final dutyFreeSummaryProvider = Provider<DutyFreeSummary?>((ref) {
  final rules = ref.watch(dutyFreeRulesProvider).value;
  final state = ref.watch(dutyFreeProvider);
  if (rules == null || !state.isReady) return null;
  return const DutyFreeCalculator().summarize(
    items: state.items,
    rules: rules,
    adult: state.adult,
  );
});

/// 영수증 글자 읽기. 테스트에서 바꾼다.
final receiptScanServiceProvider = Provider<ReceiptScanService>(
  (ref) => ReceiptScanService(ref.watch(ocrServiceProvider)),
);

/// 영수증 사진을 찍어 파일 경로를 준다. 취소하면 null. 테스트에서 바꾼다.
final receiptPhotoPickerProvider = Provider<Future<String?> Function()>((_) {
  return () async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    return photo?.path;
  };
});

/// 읽기를 마친 영수증 사진 임시 파일을 지운다. 지우지 못해도 무시한다. 테스트에서 바꾼다.
final receiptPhotoDeleterProvider = Provider<Future<void> Function(String)>((
  _,
) {
  return (path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  };
});

/// 관세청 여행자 휴대품 안내를 연다. 테스트에서 바꾼다.
final customsGuideLauncherProvider = Provider<Future<bool> Function()>((_) {
  return () => launchUrl(
    Uri.https('www.customs.go.kr', '/'),
    mode: LaunchMode.externalApplication,
  );
});

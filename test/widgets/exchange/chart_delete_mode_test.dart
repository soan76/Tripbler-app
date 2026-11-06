import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripbler/core/theme/app_theme.dart';
import 'package:tripbler/crypto/providers/crypto_provider.dart';
import 'package:tripbler/models/chart_point.dart';
import 'package:tripbler/models/exchange_rate_history_model.dart';
import 'package:tripbler/presentation/charts/chart_data_source.dart';
import 'package:tripbler/presentation/charts/chart_pair.dart';
import 'package:tripbler/presentation/charts/chart_selection_provider.dart';
import 'package:tripbler/presentation/exchange/exchange_display_provider.dart';
import 'package:tripbler/providers/auth_provider.dart';
import 'package:tripbler/providers/exchange_provider.dart';
import 'package:tripbler/providers/settings_provider.dart';
import 'package:tripbler/screens/exchange_screen.dart';
import 'package:tripbler/widgets/charts/chart_pair_carousel.dart';
import 'package:tripbler/widgets/charts/market_chart_delete_mode.dart';
import 'package:tripbler/widgets/navigation/app_drawer.dart';

import '../../crypto/crypto_test.dart' show makeApi, FiatApi;
import '../../helpers/chart_amount_finder.dart';
import '../../helpers/memory_chart_snapshots.dart';

const usd = ChartPair.fiat('USD', 'KRW');
const jpy = ChartPair.fiat('JPY', 'KRW');
const eur = ChartPair.fiat('EUR', 'KRW');

final menu = find.byKey(const ValueKey('market-chart-menu'));
final remove = find.byKey(const ValueKey('market-chart-remove'));
final layer = find.byKey(const ValueKey('market-chart-delete-layer'));

class Source implements ChartDataSource {
  @override
  Future<ChartData> load(ChartPeriod period) async {
    final now = DateTime.now();
    return ChartData(
      history: [
        for (var i = 0; i < 5; i++)
          ChartSample(
            date: now.subtract(Duration(days: 4 - i)),
            rate: 100.0 + i,
            baseCurrencyCode: 'USD',
            targetCurrencyCode: 'KRW',
          ),
      ],
      currentRate: 104,
      fetchedAt: now,
    );
  }

  @override
  void dispose() {}
}

/// 카드 지우기까지 연결된 캐러셀. 지우면 목록에서 빼고 다시 그린다.
class Charts extends StatefulWidget {
  const Charts({super.key, required this.pairs, this.addable = false});
  final List<ChartPair> pairs;

  /// 마지막 차트 추가 페이지를 둔다.
  final bool addable;

  @override
  State<Charts> createState() => _ChartsState();
}

class _ChartsState extends State<Charts> {
  late List<ChartPair> pairs = widget.pairs;
  final snapshots = MemorySnapshots();

  @override
  Widget build(BuildContext context) => ChartPairCarousel(
    pairs: pairs,
    currencies: const [],
    snapshotStore: snapshots,
    createDataSource: (_) => Source(),
    onAdd: widget.addable
        ? () => setState(
            () => pairs = [...pairs, const ChartPair.fiat('GBP', 'KRW')],
          )
        : null,
    onRemove: pairs.length > 1
        ? (index) => setState(() => pairs = [...pairs]..removeAt(index))
        : null,
  );
}

/// 금액 입력칸 아래에 캐러셀이 있고 세로로 스크롤되는 화면(환율 화면과 같은 구조).
/// [offset]까지 내리면 입력칸은 화면 밖으로 나가고 더보기는 보인다.
class FieldPage {
  FieldPage(this.tester);

  static const offset = 300.0;

  final WidgetTester tester;
  final field = FocusNode(debugLabel: 'amount');
  final scroll = ScrollController();
  ScrollPhysics? physics;
  var tabVisible = true;
  late StateSetter update;

  Widget get page => Scaffold(
    drawer: const Drawer(child: Text('서랍')),
    body: StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return IndexedStack(
          index: tabVisible ? 0 : 1,
          children: [
            SingleChildScrollView(
              controller: scroll,
              physics: physics,
              child: Column(
                children: [
                  TextField(focusNode: field),
                  const SizedBox(height: 200),
                  const Charts(pairs: [usd, jpy, eur], addable: true),
                  const SizedBox(height: 800),
                ],
              ),
            ),
            const Text('다른 탭'),
          ],
        );
      },
    ),
  );

  Future<void> pump() async {
    addTearDown(() {
      field.dispose();
      scroll.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<void> tapField() async {
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(field.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }

  Future<void> scrollTo(double pixels) async {
    scroll.jumpTo(pixels);
    await tester.pumpAndSettle();
  }

  /// 재현 순서의 앞부분: 금액 입력칸을 누르고, 내린 뒤, 더보기를 누른다.
  Future<void> openFromField() async {
    await tapField();
    await scrollTo(offset);
    await open(tester);
    expect(removeHasFocus(tester), isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  }

  Future<void> cancel() async {
    await tester.tapAt(insideCard(tester));
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
  }

  /// 입력칸으로 돌아가지 않았고, 키보드도 없고, 화면도 그 자리에 있다.
  void expectStayed({double pixels = offset}) {
    expect(field.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(scroll.offset, pixels);
    expect(tester.takeException(), isNull);
  }

  /// 초점이 어떤 버튼에도 남지 않고 화면 전체(스코프)로 갔다.
  void expectFocusReleased() {
    expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
  }
}

/// [target] 안쪽 아이콘을 품은 버튼의 초점 노드.
FocusNode buttonFocus(WidgetTester tester, Finder target) => Focus.of(
  tester.element(
    find.descendant(of: target, matching: find.byType(Icon)).first,
  ),
);

Widget app(List<ChartPair> pairs) => MaterialApp(
  home: Scaffold(body: Charts(pairs: pairs)),
);

bool menuHasFocus(WidgetTester tester) =>
    tester.widget<IconButton>(menu).focusNode!.hasFocus;

bool removeHasFocus(WidgetTester tester) =>
    tester.widget<TextButton>(remove).focusNode!.hasFocus;

FocusNode moreNode(WidgetTester tester) =>
    tester.widget<IconButton>(menu).focusNode!;

/// 삭제 버튼. 층 아래로 화면이 덮여 있어도 찾는다.
final removeAnywhere = find.byKey(
  const ValueKey('market-chart-remove'),
  skipOffstage: false,
);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> nextPage(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-700, 0));
  await tester.pumpAndSettle();
}

Future<void> previousPage(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(700, 0));
  await tester.pumpAndSettle();
}

/// Tab을 눌러 [node]에 초점이 오면 true. 한 바퀴를 넘게 돌아도 오지 않으면 false.
Future<bool> tabReaches(WidgetTester tester, FocusNode node) async {
  for (var i = 0; i < 40; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (node.hasFocus) return true;
  }
  return false;
}

/// 뒤로 가기가 실제로 동작하는지 볼 수 있게 [page]를 한 겹 쌓아 올린 앱.
Widget pushedApp(Widget page) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (c) => TextButton(
        onPressed: () =>
            Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => page)),
        child: const Text('열기'),
      ),
    ),
  ),
);

Future<void> openPushed(WidgetTester tester) async {
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

LineChartData chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

Future<void> open(WidgetTester tester) async {
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

/// 차트의 첫 점을 고른 것처럼 터치 콜백을 부른다.
void select(WidgetTester tester) {
  final chart = chartData(tester);
  final bar = chart.lineBarsData.first;
  chart.lineTouchData.touchCallback!(
    FlTapDownEvent(TapDownDetails()),
    LineTouchResponse(
      touchLocation: Offset.zero,
      touchChartCoordinate: Offset.zero,
      lineBarSpots: [TouchLineBarSpot(bar, 0, bar.spots[1], 0)],
    ),
  );
}

/// 화면 낭독기 트리에 [tooltip]이 있는 노드가 있는지.
bool semanticsHasTooltip(WidgetTester tester, String tooltip) {
  var found = false;
  bool visit(SemanticsNode node) {
    if (node.getSemanticsData().tooltip == tooltip) found = true;
    node.visitChildren(visit);
    return true;
  }

  var root = tester.getSemantics(find.byType(Charts));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return found;
}

/// 화면 낭독기 트리의 모든 노드.
List<SemanticsData> semanticsNodes(WidgetTester tester) {
  final nodes = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    nodes.add(node.getSemanticsData());
    node.visitChildren(visit);
    return true;
  }

  var root = tester.getSemantics(find.byType(Charts));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return nodes;
}

/// 대비 계산과 넘침 확인에 쓰는, 설정을 바꿀 수 있는 앱.
Widget configuredApp({
  ThemeData? theme,
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: child!,
  ),
  home: const Scaffold(body: Charts(pairs: [usd, jpy])),
);

double layerOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: layer, matching: find.byType(Opacity)).first,
    )
    .opacity;

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// 세로 스크롤만 옮겨 [target]을 화면 위쪽에 보이게 한다. tester.ensureVisible은 가로
/// PageView까지 옮겨 다른 카드로 넘어가므로 쓰지 않는다.
Future<void> revealVertically(
  WidgetTester tester,
  Finder target,
  ScrollPosition position,
) async {
  position.jumpTo(position.pixels + tester.getTopLeft(target).dy - 80);
  await tester.pumpAndSettle();
}

/// 카드 위쪽 모서리 근처. 버튼 밖이면서 카드 안이다.
Offset insideCard(WidgetTester tester) =>
    tester.getTopLeft(layer) + const Offset(30, 30);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('more opens a delete layer on the card, without a popup', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(layer, findsNothing);
    expect(find.byType(PopupMenuButton<void>), findsNothing);

    await open(tester);
    expect(find.byType(PopupMenuItem<void>), findsNothing);
    expect(layer, findsOneWidget);
    // 층은 카드 전체를 덮고, 내용은 비쳐 보인다.
    expect(tester.getSize(layer).height, greaterThan(300));
    final overlay = tester.widget<ColoredBox>(
      find.descendant(of: layer, matching: find.byType(ColoredBox)).first,
    );
    expect(overlay.color.a, inExclusiveRange(0, 1));

    // 버튼은 가운데의 배경·테두리 없는 빨간 글자 버튼이다.
    expect(tester.getCenter(remove), tester.getCenter(layer));
    final context = tester.element(remove);
    final colors = Theme.of(context).colorScheme;
    final text = tester.widget<Text>(find.text('차트 삭제'));
    expect(text.data, '차트 삭제');
    final style = tester.widget<TextButton>(remove).style!;
    expect(style.foregroundColor!.resolve({}), colors.error);
    final material = tester.widget<Material>(
      find.descendant(of: remove, matching: find.byType(Material)).first,
    );
    expect(material.color, anyOf(isNull, Colors.transparent));
    expect((material.shape! as OutlinedBorder).side, BorderSide.none);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the button deletes that chart', (tester) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('USD'), findsNothing);
    expect(find.text('JPY').hitTestable(), findsOneWidget);
    expect(remove, findsNothing);
    // 마지막 한 장은 지울 수 없어 더보기도 없다.
    expect(menu, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focus moves to the button and returns to more on cancel', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();

    await open(tester);
    expect(removeHasFocus(tester), isTrue);

    await tester.tapAt(insideCard(tester));
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(menuHasFocus(tester), isTrue);

    // Esc로 닫아도 같다.
    await open(tester);
    expect(removeHasFocus(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(menuHasFocus(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping anywhere on the card but the button closes the mode', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    final menuCenter = tester.getCenter(menu);
    final swapCenter = tester.getCenter(
      find.byKey(const ValueKey('market-chart-swap')),
    );
    final chartCenter = tester.getCenter(find.byType(LineChart));

    for (final point in [menuCenter, swapCenter, chartCenter]) {
      await open(tester);
      expect(remove, findsOneWidget);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
    }
    // 아래 스왑 버튼이나 차트에는 탭이 닿지 않았다.
    expect(amountField('USD'), findsOneWidget);
    expect(chartData(tester).lineBarsData.first.showingIndicators, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back closes the mode first and then leaves the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              return TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Charts(pairs: [usd, jpy])),
                  ),
                ),
                child: const Text('열기'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(menu, findsOneWidget);
    expect(menuHasFocus(tester), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(find.text('열기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chart touch and marker are off while the mode is open', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    expect(chartData(tester).lineTouchData.enabled, isTrue);

    // 떠 있던 마커는 모드를 열면 사라진다.
    select(tester);
    await tester.pump();
    expect(chartData(tester).lineBarsData.first.showingIndicators, isNotEmpty);

    await open(tester);
    expect(chartData(tester).lineTouchData.enabled, isFalse);
    expect(chartData(tester).lineBarsData.first.showingIndicators, isEmpty);
    // 차트 위를 눌러도 층이 받는다.
    expect(
      find
          .descendant(of: layer, matching: find.byType(ColoredBox))
          .hitTestable(at: Alignment.center),
      findsWidgets,
    );

    // 닫으면 다시 켜지고, 닫는 탭으로 마커가 생기지 않는다.
    await tester.tapAt(tester.getCenter(find.byType(LineChart)));
    await tester.pumpAndSettle();
    expect(chartData(tester).lineTouchData.enabled, isTrue);
    expect(chartData(tester).lineBarsData.first.showingIndicators, isEmpty);

    select(tester);
    await tester.pump();
    expect(chartData(tester).lineBarsData.first.showingIndicators, isNotEmpty);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('content under the layer leaves the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    expect(semanticsHasTooltip(tester, '차트 메뉴'), isTrue);

    await open(tester);
    expect(semanticsHasTooltip(tester, '차트 메뉴'), isFalse);
    expect(find.bySemanticsLabel('차트 삭제'), findsOneWidget);
    expect(
      tester.getSemantics(remove),
      containsSemantics(label: '차트 삭제', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moving to another page closes the mode', (tester) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    await open(tester);

    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('JPY').hitTestable(), findsOneWidget);
    expect(remove, findsNothing);

    await tester.drag(find.byType(PageView), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('USD').hitTestable(), findsOneWidget);
    expect(remove, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('shouldLoad on the mode itself', () {
    late FocusNode moreFocus;

    Widget mode({required bool shouldLoad}) => MaterialApp(
      home: Scaffold(
        body: MarketChartDeleteMode(
          onRemove: () {},
          shouldLoad: shouldLoad,
          borderRadius: 22,
          builder: (context, controls) {
            moreFocus = controls.moreFocusNode;
            return IconButton(
              key: const ValueKey('market-chart-menu'),
              focusNode: controls.moreFocusNode,
              onPressed: controls.open,
              icon: const Icon(Icons.more_vert),
            );
          },
        ),
      ),
    );

    Future<void> openMode(WidgetTester tester) async {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
    }

    testWidgets('turning it off closes the mode and leaves focus alone', (
      tester,
    ) async {
      await tester.pumpWidget(mode(shouldLoad: true));
      await openMode(tester);

      await tester.pumpWidget(mode(shouldLoad: false));
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      // 사용자가 취소한 것이 아니므로 더보기로 초점을 돌려주지 않는다.
      expect(moreFocus.hasFocus, isFalse);
    });

    testWidgets('a card that was already off keeps the mode', (tester) async {
      await tester.pumpWidget(mode(shouldLoad: false));
      await openMode(tester);

      await tester.pumpWidget(mode(shouldLoad: false));
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);

      await tester.pumpWidget(mode(shouldLoad: true));
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
    });
  });

  testWidgets('a hidden card closes the mode and does not block back', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      pushedApp(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return IndexedStack(
                index: visible ? 0 : 1,
                children: const [
                  Charts(pairs: [usd, jpy]),
                  Text('다른 탭'),
                ],
              );
            },
          ),
        ),
      ),
    );
    await openPushed(tester);
    await open(tester);
    expect(remove, findsOneWidget);

    update(() => visible = false);
    await tester.pumpAndSettle();
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(remove, findsNothing);

    // 탭을 옮긴 사이 뒤로 가기는 모드에 막히지 않고 화면을 떠난다.
    await open(tester);
    expect(remove, findsOneWidget);
    update(() => visible = false);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Charts), findsNothing);
    expect(find.text('열기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // 숨겨질 때 버튼에 초점이 없으면 초점 변화로는 알 수 없어 Visibility로 닫아야 한다.
  testWidgets('a card hidden under a bottom sheet does not block back', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      pushedApp(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return IndexedStack(
                index: visible ? 0 : 1,
                children: const [
                  Charts(pairs: [usd, jpy]),
                  Text('다른 탭'),
                ],
              );
            },
          ),
        ),
      ),
    );
    await openPushed(tester);
    await open(tester);

    showModalBottomSheet<void>(
      context: tester.element(find.byType(Charts)),
      builder: (_) => const Text('위에 올라온 것'),
    );
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('위에 올라온 것'), findsNothing);
    expect(removeAnywhere, findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a card on another page cannot be reached from the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy, eur]));
    await tester.pumpAndSettle();

    await open(tester);
    await press(tester, LogicalKeyboardKey.escape);
    final hiddenMore = moreNode(tester);
    expect(hiddenMore.hasFocus, isTrue);

    // 넘기면 초점이 숨은 카드에 남지 않는다.
    await nextPage(tester);
    expect(find.text('JPY').hitTestable(), findsOneWidget);
    expect(hiddenMore.hasFocus, isFalse);

    // Enter를 두 번 눌러도 숨은 USD 카드는 열리지도 지워지지도 않는다.
    await press(tester, LogicalKeyboardKey.enter);
    expect(removeAnywhere, findsNothing);
    await press(tester, LogicalKeyboardKey.enter);
    expect(removeAnywhere, findsNothing);
    expect(find.text('USD', skipOffstage: false), findsOneWidget);
    expect(find.text('JPY').hitTestable(), findsOneWidget);

    // Tab으로도 숨은 카드에 들어가지 못한다.
    expect(await tabReaches(tester, hiddenMore), isFalse);
    expect(removeAnywhere, findsNothing);

    // 돌아오면 키보드로 더보기에 다시 갈 수 있고 삭제 모드도 열린다.
    await previousPage(tester);
    expect(find.text('USD').hitTestable(), findsOneWidget);
    expect(await tabReaches(tester, hiddenMore), isTrue);
    await press(tester, LogicalKeyboardKey.enter);
    expect(remove, findsOneWidget);
    expect(removeHasFocus(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with loading off the current card still takes keyboard focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChartPairCarousel(
            pairs: const [usd, jpy],
            currencies: const [],
            // shouldLoad는 모든 카드에서 false지만 지금 보이는 카드는 조작할 수 있다.
            active: false,
            snapshotStore: MemorySnapshots(),
            createDataSource: (_) => Source(),
            onRemove: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = moreNode(tester);
    expect(await tabReaches(tester, first), isTrue);

    await nextPage(tester);
    expect(first.hasFocus, isFalse);
    expect(await tabReaches(tester, first), isFalse);
    expect(await tabReaches(tester, moreNode(tester)), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening a drawer closes the mode and back closes the drawer', (
    tester,
  ) async {
    // 실제 화면(MainScreen)과 같은 구조: 같은 route의 Scaffold에 AppDrawer를 둔다.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: Scaffold(
            drawer: const AppDrawer(),
            body: SafeArea(
              child: Column(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const Expanded(
                    child: SingleChildScrollView(
                      child: Charts(pairs: [usd, jpy]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final more = moreNode(tester);
    await open(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(removeAnywhere, findsNothing);
    expect(more.hasFocus, isFalse);

    // 첫 번째 뒤로 가기가 서랍을 닫고, 초점을 서랍 밑으로 빼앗지 않는다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(more.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focusing a text field closes the mode and keeps the focus', (
    tester,
  ) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      pushedApp(
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TextField(focusNode: field),
                const Charts(pairs: [usd, jpy]),
              ],
            ),
          ),
        ),
      ),
    );
    await openPushed(tester);
    final more = moreNode(tester);

    // 입력창에 초점이 있을 때 열어도, 버튼이 초점을 받기 전에 닫히지 않는다.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pump();
    expect(remove, findsOneWidget);
    await tester.pumpAndSettle();
    expect(remove, findsOneWidget);
    expect(removeHasFocus(tester), isTrue);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(field.hasFocus, isTrue);
    expect(more.hasFocus, isFalse);

    // 뒤로 가기는 입력창 초점을 빼앗아 더보기로 옮기지 않고 화면을 떠난다.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tab out of the layer closes the mode where focus went', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    final more = moreNode(tester);
    await open(tester);

    await press(tester, LogicalKeyboardKey.tab);
    expect(remove, findsNothing);
    expect(more.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (name, cover) in <(String, Future<void> Function(BuildContext))>[
    (
      'a bottom sheet',
      (c) => showModalBottomSheet<void>(
        context: c,
        builder: (_) => const Text('위에 올라온 것'),
      ),
    ),
    (
      'a pushed screen',
      (c) => Navigator.of(c).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('위에 올라온 것')),
        ),
      ),
    ),
  ]) {
    testWidgets('$name above keeps the mode and gives focus back', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (c) => TextButton(
                    onPressed: () => cover(c),
                    child: const Text('덮기'),
                  ),
                ),
                const Expanded(
                  child: SingleChildScrollView(
                    child: Charts(pairs: [usd, jpy]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
      final button = tester.widget<TextButton>(remove).focusNode!;

      await tester.tap(find.text('덮기'));
      await tester.pumpAndSettle();
      expect(find.text('위에 올라온 것'), findsOneWidget);
      expect(button.hasFocus, isFalse);
      expect(removeAnywhere, findsOneWidget);

      // 첫 번째 뒤로 가기는 위의 것만 닫고, 모드와 초점은 그대로 돌아온다.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('위에 올라온 것'), findsNothing);
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);

      // 그다음 뒤로 가기는 모드를 닫고 더보기로 돌아간다.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect(menuHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // 초점 관리자가 앱 비활성화에 반응하는 것은 데스크톱·웹이다(모바일은 초점이 그대로다).
  testWidgets(
    'leaving the app keeps the mode and gives focus back',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await tester.pumpWidget(app(const [usd, jpy]));
      await tester.pumpAndSettle();
      await open(tester);
      final button = tester.widget<TextButton>(remove).focusNode!;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(button.hasFocus, isFalse);
      expect(remove, findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('content under the layer cannot take focus', (tester) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    final more = moreNode(tester);
    await open(tester);

    more.requestFocus();
    await tester.pump();
    expect(more.hasFocus, isFalse);
    expect(remove, findsOneWidget);
    expect(removeHasFocus(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mode is one announced button with a dismiss action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();

    await tester.tap(menu);
    // 첫 프레임은 투명도 0이지만 화면 낭독기에는 처음부터 있어야 알릴 수 있다.
    await tester.pump();
    expect(layerOpacity(tester), 0);
    expect(find.bySemanticsLabel('차트 삭제'), findsOneWidget);
    await tester.pumpAndSettle();

    // 알림과 닫기는 라벨이 있는 버튼 노드에 있다. 라이브 영역은 라벨로 알리므로
    // 라벨 없는 노드가 맡으면 읽을 내용이 없다.
    expect(
      tester.getSemantics(remove),
      containsSemantics(
        label: '차트 삭제',
        isButton: true,
        isLiveRegion: true,
        hasTapAction: true,
        hasDismissAction: true,
      ),
    );
    final nodes = semanticsNodes(tester);
    // 같은 라벨이 두 번 읽히지 않고, 라벨 없는 빈 칸도 생기지 않는다.
    expect(nodes.where((n) => n.label.contains('차트 삭제')), hasLength(1));
    expect(
      nodes.where(
        (n) =>
            n.label.isEmpty &&
            (n.flagsCollection.isLiveRegion ||
                n.hasAction(SemanticsAction.dismiss)),
      ),
      isEmpty,
    );

    // 화면 낭독기의 닫기 동작은 다른 취소와 같이 더보기로 돌아온다.
    final button = tester.getSemantics(remove);
    button.owner!.performAction(button.id, SemanticsAction.dismiss);
    await tester.pumpAndSettle();
    expect(remove, findsNothing);
    expect(menuHasFocus(tester), isTrue);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mode closes as soon as the card cannot be removed', (
    tester,
  ) async {
    var removable = true;
    late StateSetter update;
    final snapshots = MemorySnapshots();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ChartPairCarousel(
                pairs: const [usd, jpy],
                currencies: const [],
                snapshotStore: snapshots,
                createDataSource: (_) => Source(),
                onRemove: removable ? (_) {} : null,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await open(tester);

    update(() => removable = false);
    // 다음 프레임에 눌리지 않는 버튼이 남아 있지 않다.
    await tester.pump();
    expect(remove, findsNothing);
    expect(menu, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('the red label stays readable over the layer in $name', (
      tester,
    ) async {
      await tester.pumpWidget(configuredApp(theme: theme));
      await tester.pumpAndSettle();
      await open(tester);

      final colors = theme.colorScheme;
      final overlay = tester
          .widget<ColoredBox>(
            find.descendant(of: layer, matching: find.byType(ColoredBox)).first,
          )
          .color;
      // 가운데에 올 수 있는 내용(그래프 선, 흐린 안내문, 빈 카드) 위에서 잰다.
      for (final content in [
        colors.primary,
        colors.onSurfaceVariant,
        colors.surface,
      ]) {
        expect(
          contrast(colors.error, Color.alphaBlend(overlay, content)),
          greaterThanOrEqualTo(4.5),
        );
      }
      // 큰 글자 배율 등으로 글자(onSurface)가 버튼 뒤에 올 때. 라이트 테마는 지금 층
      // 농도(0.82)에서 4.25로 4.5에 못 미친다. 농도는 화면을 보고 정할 값이라 그대로
      // 두고, 값이 바뀌면 알 수 있게 실제 값을 적어 둔다.
      final overText = contrast(
        colors.error,
        Color.alphaBlend(overlay, colors.onSurface),
      );
      expect(
        overText,
        name == 'light' ? closeTo(4.25, 0.01) : greaterThanOrEqualTo(4.5),
      );
      // 내용은 사라지지 않고 비쳐 보인다.
      expect(overlay.a, lessThan(0.9));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the layer uses no glass effect', (tester) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pressing dims the label without showing a surface', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    await open(tester);

    final style = tester.widget<TextButton>(remove).style!;
    expect(style.splashFactory, NoSplash.splashFactory);
    expect(style.overlayColor!.resolve({WidgetState.pressed})!.a, 0);
    expect(style.overlayColor!.resolve({})!.a, 0);
    expect(
      style.foregroundColor!.resolve({WidgetState.pressed})!.a,
      lessThan(style.foregroundColor!.resolve({})!.a),
    );

    // 키보드 초점 표시는 남기고, 모양은 4dp 사각형이다.
    expect(
      style.overlayColor!.resolve({WidgetState.focused})!.a,
      greaterThan(0),
    );
    expect(
      style.shape!.resolve({}),
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a focus surface shows for the keyboard but not for touch', (
    tester,
  ) async {
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await open(tester);
    expect(removeHasFocus(tester), isTrue);
    final ink = Material.of(tester.element(find.text('차트 삭제')));
    expect(ink, paintsExactlyCountTimes(#drawRect, 0));

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpAndSettle();
    expect(ink, paintsExactlyCountTimes(#drawRect, 1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the button fits a narrow card at 1.3x text with a 48dp target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(configuredApp(textScale: 1.3));
    await tester.pumpAndSettle();
    await open(tester);

    expect(tester.takeException(), isNull);
    final button = tester.getRect(remove);
    expect(button.height, greaterThanOrEqualTo(48));
    expect(button.width, greaterThanOrEqualTo(48));
    final card = tester.getRect(layer);
    expect(button.left, greaterThanOrEqualTo(card.left));
    expect(button.right, lessThanOrEqualTo(card.right));
    expect(button.center, card.center);

    final label = tester.getRect(find.text('차트 삭제'));
    expect(label.left, greaterThanOrEqualTo(button.left));
    expect(label.right, lessThanOrEqualTo(button.right));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the layer fades in but works from its first frame', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();

    await tester.tap(menu);
    await tester.pump();
    expect(layerOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 50));
    expect(layerOpacity(tester), inExclusiveRange(0, 1));
    // 전환 중에도 초점은 이미 버튼에 있고, 눌러서 지울 수 있다.
    expect(removeHasFocus(tester), isTrue);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('USD'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing removes the layer at once, so taps are not swallowed', (
    tester,
  ) async {
    await tester.pumpWidget(app(const [usd, jpy]));
    await tester.pumpAndSettle();
    await open(tester);

    await tester.tapAt(insideCard(tester));
    await tester.pump();
    expect(layer, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows the layer without a fade', (tester) async {
    await tester.pumpWidget(configuredApp(disableAnimations: true));
    await tester.pumpAndSettle();

    await tester.tap(menu);
    await tester.pump();
    expect(layerOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  group('a text field used earlier does not take focus back', () {
    testWidgets('cancel returns to more, and paging stays where it is', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      await page.cancel();
      expect(menuHasFocus(tester), isTrue);
      page.expectStayed();

      await nextPage(tester);
      expect(find.text('JPY').hitTestable(), findsOneWidget);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('deleting the chart', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('USD', skipOffstage: false), findsNothing);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('paging with the mode open', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      await nextPage(tester);
      expect(removeAnywhere, findsNothing);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opening the drawer and going back', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      expect(removeAnywhere, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a bottom sheet above, then cancel and paging', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      showModalBottomSheet<void>(
        context: tester.element(find.byType(Charts)),
        builder: (_) => const Text('시트'),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(removeHasFocus(tester), isTrue);
      page.expectStayed();

      await page.cancel();
      expect(menuHasFocus(tester), isTrue);
      await nextPage(tester);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switching tabs and coming back', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();

      page.update(() => page.tabVisible = false);
      await tester.pumpAndSettle();
      expect(removeAnywhere, findsNothing);
      page.expectStayed();

      page.update(() => page.tabVisible = true);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      page.expectStayed();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('changing the period with the mode open', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.tapField();
      await page.scrollTo(150);
      await open(tester);

      await tester.tap(find.text('3M'));
      await tester.pumpAndSettle();
      page.expectStayed(pixels: 150);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('more pressed from the keyboard, then cancel and paging', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.tapField();
      moreNode(tester).requestFocus();
      await tester.pumpAndSettle();
      await page.scrollTo(FieldPage.offset);

      await press(tester, LogicalKeyboardKey.enter);
      expect(removeHasFocus(tester), isTrue);
      page.expectStayed();

      await page.cancel();
      expect(menuHasFocus(tester), isTrue);
      await nextPage(tester);
      page.expectStayed();
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    for (final (name, target) in [
      ('more', menu),
      ('swap', find.byKey(const ValueKey('market-chart-swap'))),
    ]) {
      testWidgets('paging away with focus on $name, without the mode', (
        tester,
      ) async {
        final page = FieldPage(tester);
        await page.pump();
        await page.tapField();
        buttonFocus(tester, target).requestFocus();
        await tester.pumpAndSettle();
        await page.scrollTo(FieldPage.offset);

        await nextPage(tester);
        expect(find.text('JPY').hitTestable(), findsOneWidget);
        page.expectStayed();
        page.expectFocusReleased();
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('swap pressed from the keyboard keeps its focus', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.tapField();
      await page.scrollTo(FieldPage.offset);
      final swap = find.byKey(const ValueKey('market-chart-swap'));
      final node = buttonFocus(tester, swap);
      node.requestFocus();
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.enter);
      expect(amountField('KRW'), findsOneWidget);
      expect(buttonFocus(tester, swap), same(node));
      expect(node.hasFocus, isTrue);
      page.expectStayed();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('changing the period with focus in the card', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.tapField();
      moreNode(tester).requestFocus();
      await tester.pumpAndSettle();
      await page.scrollTo(150);

      await tester.tap(find.text('3M'));
      await tester.pumpAndSettle();
      page.expectStayed(pixels: 150);
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    Future<void> focusAdd(WidgetTester tester, FieldPage page) async {
      await page.tapField();
      await page.scrollTo(150);
      for (var i = 0; i < 3; i++) {
        await nextPage(tester);
      }
      final add = find.byKey(const ValueKey('market-chart-add'));
      expect(add, findsOneWidget);
      buttonFocus(tester, add).requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('adding a chart with focus on the add button', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await focusAdd(tester, page);

      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('GBP').hitTestable(), findsOneWidget);
      page.expectStayed(pixels: 150);
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving the add page with focus on its button', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await focusAdd(tester, page);

      await previousPage(tester);
      page.expectStayed(pixels: 150);
      page.expectFocusReleased();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a focused text field keeps the keyboard while paging', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.tapField();
      await page.scrollTo(FieldPage.offset);

      await nextPage(tester);
      expect(find.text('JPY').hitTestable(), findsOneWidget);
      expect(page.field.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(page.scroll.offset, FieldPage.offset);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping the field again after cancel shows the keyboard', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.openFromField();
      await page.cancel();

      await page.scrollTo(0);
      await page.tapField();
      await nextPage(tester);
      expect(page.field.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('on the real exchange screen', (tester) async {
      // 차트가 가려질 만큼 낮은 화면(키보드가 내려간 작은 기기 정도).
      tester.view.physicalSize = const Size(2400, 1200);
      addTearDown(tester.view.reset);
      final api = makeApi();
      final crypto = CryptoProvider(api: api);
      final fiatApi = FiatApi();
      final exchange = ExchangeProvider(apiService: fiatApi);
      final display = ExchangeDisplayProvider(
        exchange,
        crypto,
        fiatApi: fiatApi,
      );
      final charts = ChartSelectionProvider();
      await display.initialize();
      addTearDown(() {
        charts.dispose();
        display.dispose();
        exchange.dispose();
        crypto.dispose();
        api.dispose();
        fiatApi.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: crypto),
            ChangeNotifierProvider.value(value: exchange),
            ChangeNotifierProvider.value(value: display),
            ChangeNotifierProvider.value(value: charts),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: ExchangeScreen())),
        ),
      );
      await tester.pumpAndSettle();

      final amount = find.byType(TextField).first;
      await tester.tap(amount);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      final amountFocus = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      expect(amountFocus.hasFocus, isTrue);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;

      await revealVertically(tester, menu, position);
      final pixels = position.pixels;
      expect(pixels, greaterThan(0));
      // 세로로만 옮겨 첫 카드에서 시작한다.
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        0,
      );
      expect(
        find.byKey(const ValueKey('market-chart-pick-fiat:USD')).hitTestable(),
        findsOneWidget,
      );

      void expectStayed() {
        expect(tester.testTextInput.isVisible, isFalse);
        expect(position.pixels, pixels);
        expect(amountFocus.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
      }

      // 취소 후 넘기기.
      await open(tester);
      await tester.tapAt(tester.getCenter(menu));
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect(menuHasFocus(tester), isTrue);
      expectStayed();
      await nextPage(tester);
      expectStayed();
      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());

      // 다시 입력칸을 쓰고 차트를 지운다.
      await tester.ensureVisible(amount);
      await tester.pumpAndSettle();
      await tester.tap(amount);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      position.jumpTo(pixels);
      await tester.pumpAndSettle();
      final countBefore = charts.pairs.length;
      await open(tester);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(charts.pairs, hasLength(countBefore - 1));
      expectStayed();

      // 화면 밖으로 내리면 모드가 닫히고 Enter로 지워지지 않는다.
      await open(tester);
      await revealVertically(tester, remove, position);
      expect(remove, findsOneWidget);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(removeAnywhere, findsNothing);
      await press(tester, LogicalKeyboardKey.enter);
      expect(charts.pairs, hasLength(countBefore - 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('opening with focus on a scope keeps the outer scope history', (
    tester,
  ) async {
    final field = FocusNode(debugLabel: 'field');
    final inner = FocusScopeNode(debugLabel: 'inner');
    addTearDown(() {
      field.dispose();
      inner.dispose();
    });
    var showInner = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Column(
                children: [
                  TextField(focusNode: field),
                  if (showInner)
                    Expanded(
                      child: FocusScope(
                        node: inner,
                        child: const Charts(pairs: [usd, jpy]),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    field.requestFocus();
    await tester.pump();
    inner.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(inner));

    await open(tester);
    expect(removeHasFocus(tester), isTrue);
    await tester.tapAt(insideCard(tester));
    await tester.pumpAndSettle();

    // 스코프 자체에 있던 초점을 풀면 바깥 스코프의 기록이 지워져 이 복귀가 일어나지 않는다.
    update(() => showInner = false);
    await tester.pumpAndSettle();
    expect(field.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  group('scrolling the card out of the viewport', () {
    testWidgets('a small vertical drag keeps the mode and its focus', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      await tester.drag(layer, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(page.scroll.offset, lessThan(FieldPage.offset));
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dragging it away closes the mode without returning focus', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      final more = moreNode(tester);
      await open(tester);

      // 끄는 동안 프레임마다 재고, 층을 끄는 도중 닫혀도 예외가 없어야 한다.
      final gesture = await tester.startGesture(tester.getCenter(layer));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(page.scroll.offset, greaterThan(FieldPage.offset + 100));
      expect(remove, findsNothing);
      expect(more.hasFocus, isFalse);
      page.expectFocusReleased();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a fling closes it too', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      await tester.fling(layer, const Offset(0, -300), 2000);
      await tester.pumpAndSettle();
      expect(remove, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it stays while the button center is inside, not after', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      final center = tester.getCenter(remove).dy;
      await page.scrollTo(FieldPage.offset + center - 2);
      expect(remove, findsOneWidget);
      expect(tester.getCenter(remove).dy, closeTo(2, 0.01));

      await page.scrollTo(FieldPage.offset + center + 2);
      expect(remove, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after closing, back leaves the screen at once', (
      tester,
    ) async {
      final page = FieldPage(tester);
      addTearDown(() {
        page.field.dispose();
        page.scroll.dispose();
      });
      await tester.pumpWidget(pushedApp(page.page));
      await openPushed(tester);
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      await page.scrollTo(FieldPage.offset + 600);
      expect(removeAnywhere, findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Charts), findsNothing);
      expect(find.text('열기'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after closing, Enter deletes nothing', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      await page.scrollTo(FieldPage.offset + 600);
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.text('USD', skipOffstage: false), findsOneWidget);
      expect(removeAnywhere, findsNothing);

      // 돌아와도 모드는 닫혀 있고 다시 열 수 있다.
      await page.scrollTo(FieldPage.offset);
      expect(remove, findsNothing);
      await open(tester);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    // 화면이 낮으면 맨 위에서 더보기는 보이고 삭제 버튼 가운데는 아래로 가려진다.
    Future<FieldPage> openWithButtonHidden(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 1410);
      addTearDown(tester.view.reset);
      final page = FieldPage(tester);
      await page.pump();
      await open(tester);
      expect(tester.getCenter(remove).dy, greaterThan(470));
      return page;
    }

    testWidgets('a button hidden from the start stays until the card leaves', (
      tester,
    ) async {
      final page = await openWithButtonHidden(tester);

      await page.scrollTo(2);
      expect(tester.getCenter(remove).dy, greaterThan(470));
      expect(remove, findsOneWidget);

      await page.scrollTo(FieldPage.offset + 800);
      expect(removeAnywhere, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a button revealed once closes when it is hidden again', (
      tester,
    ) async {
      final page = await openWithButtonHidden(tester);

      await page.scrollTo(150);
      expect(tester.getCenter(remove).dy, lessThan(470));
      expect(remove, findsOneWidget);

      await page.scrollTo(0);
      expect(remove, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reopening with the button hidden again keeps the mode', (
      tester,
    ) async {
      final page = await openWithButtonHidden(tester);

      // 지난번에 버튼을 봤어도 새로 연 모드에서는 아직 보지 않은 것으로 센다.
      await page.scrollTo(150);
      await page.cancel();
      await page.scrollTo(0);
      await open(tester);
      expect(tester.getCenter(remove).dy, greaterThan(470));
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a horizontal drag that does not change the page keeps it', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      final gesture = await tester.startGesture(tester.getCenter(layer));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(remove, findsOneWidget);
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without a vertical scroll view the mode stays', (
      tester,
    ) async {
      await tester.pumpWidget(app(const [usd, jpy]));
      await tester.pumpAndSettle();
      await open(tester);

      // 화면 크기가 바뀌어도 잴 스크롤이 없으니 PageView를 세로 스크롤로 착각하지 않는다.
      tester.view.physicalSize = const Size(2400, 900);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      tester.takeException(); // 좁아진 화면의 넘침은 이 시험과 무관하다.
      expect(remove, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a replaced scroll position is followed', (tester) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      // 스크롤 물리를 바꾸면 Scrollable이 위치 객체를 새로 만든다.
      final old = page.scroll.position;
      page.update(() => page.physics = const BouncingScrollPhysics());
      await tester.pumpAndSettle();
      expect(page.scroll.position, isNot(same(old)));
      expect(remove, findsOneWidget);

      await page.scrollTo(FieldPage.offset + 600);
      expect(remove, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a keyboard shrinking the viewport does not close it', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      // 위의 입력창이 닫힌 직후처럼 키보드가 내려가는 중이면 버튼이 잠시 가려진다.
      tester.view.viewInsets = const FakeViewPadding(bottom: 1500);
      await tester.pumpAndSettle();
      expect(tester.getCenter(remove).dy, greaterThan(100));
      expect(remove, findsOneWidget);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a keyboard going down leaves a hidden card to be closed', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 1500);
      await tester.pumpAndSettle();
      await page.scrollTo(FieldPage.offset + 600);
      expect(removeAnywhere, findsOneWidget);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(removeAnywhere, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a smaller screen that hides the button closes it', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);
      expect(remove, findsOneWidget);

      // 회전처럼 스크롤 위치는 그대로인 채 화면만 작아진다.
      tester.view.physicalSize = const Size(2400, 300);
      await tester.pumpAndSettle();
      expect(page.scroll.offset, FieldPage.offset);
      expect(remove, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sheet above keeps the mode while the page moves', (
      tester,
    ) async {
      final page = FieldPage(tester);
      await page.pump();
      await page.scrollTo(FieldPage.offset);
      await open(tester);

      showModalBottomSheet<void>(
        context: tester.element(find.byType(Charts)),
        builder: (_) => const Text('시트'),
      );
      await tester.pumpAndSettle();
      await page.scrollTo(FieldPage.offset + 600);
      expect(removeAnywhere, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await page.scrollTo(FieldPage.offset);
      expect(remove, findsOneWidget);
      expect(removeHasFocus(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/mini_graph_pin.dart';
import 'package:se_knowledge/services/settings_service.dart';
import 'package:se_knowledge/state/app_state.dart';
import 'package:se_knowledge/views/widgets/floating_mini_graph.dart';
import 'package:se_knowledge/views/widgets/mini_graph_panel.dart';
import 'package:se_knowledge/views/widgets/sidebar_mini_graph.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cửa sổ đồ thị thu nhỏ nhiều trang: phần mô hình thuần Dart (lật trang,
/// ghim, gỡ, đổi thứ tự, dọn khung, lưu đĩa) và phần giao diện một cửa sổ.
void main() {
  MiniGraphPins pages(List<String?> codes, [int active = 0]) =>
      MiniGraphPins(codes, active);

  group('MiniGraphPins — ghim', () {
    test('ghim khung mới thì thêm vào cuối và chuyển tới trang đó', () {
      final p = MiniGraphPins.empty.pin('A').pin('B');
      expect(p.codes, ['A', 'B']);
      expect(p.activeIndex, 1);
      expect(p.activeCode, 'B');
    });

    test('ghim khung đã có thì chỉ chuyển trang, không thêm trùng', () {
      final p = pages(['A', 'B', 'C'], 2).pin('A');
      expect(p.codes, ['A', 'B', 'C']);
      expect(p.activeIndex, 0);
    });

    test('trang "toàn bộ môn" (null) ghim được và không bị trùng', () {
      final p = MiniGraphPins.empty.pin(null).pin('A').pin(null);
      expect(p.codes, [null, 'A']);
      expect(p.activeCode, isNull);
      expect(p.activeIndex, 0);
    });

    test('đủ maxPages thì ghim khung mới không đổi gì', () {
      var p = MiniGraphPins.empty;
      for (var i = 0; i < MiniGraphPins.maxPages; i++) {
        p = p.pin('K$i');
      }
      expect(p.isFull, isTrue);
      final after = p.pin('MOI');
      expect(identical(after, p), isTrue);
      expect(after.length, MiniGraphPins.maxPages);
      // Khung đã có thì vẫn chuyển trang được dù đã đủ.
      expect(p.pin('K0').activeIndex, 0);
    });
  });

  group('MiniGraphPins — gỡ', () {
    test('gỡ trang đang xem ở giữa thì sang trang bên trái', () {
      final p = pages(['A', 'B', 'C'], 1).unpin('B');
      expect(p.codes, ['A', 'C']);
      expect(p.activeCode, 'A');
    });

    test('gỡ trang đầu đang xem thì sang trang kế bên phải', () {
      final p = pages(['A', 'B', 'C'], 0).unpin('A');
      expect(p.codes, ['B', 'C']);
      expect(p.activeCode, 'B');
    });

    test('gỡ trang cuối đang xem thì lùi về trang trước nó', () {
      final p = pages(['A', 'B', 'C'], 2).unpin('C');
      expect(p.activeCode, 'B');
      expect(p.activeIndex, 1);
    });

    test('gỡ trang duy nhất thì về rỗng, activeIndex = 0', () {
      final p = pages(['A']).unpin('A');
      expect(p.isEmpty, isTrue);
      expect(p.activeIndex, 0);
    });

    test('gỡ trang khác thì vẫn xem đúng khung cũ', () {
      final p = pages(['A', 'B', 'C'], 2).unpin('A');
      expect(p.activeCode, 'C');
      expect(p.activeIndex, 1);
      expect(pages(['A', 'B', 'C'], 0).unpin('C').activeCode, 'A');
    });

    test('gỡ khung không có thì trả về chính nó', () {
      final p = pages(['A', 'B']);
      expect(identical(p.unpin('X'), p), isTrue);
    });
  });

  group('MiniGraphPins — đổi thứ tự và dọn khung', () {
    test('reorder giữ đúng khung đang xem theo mã chứ không theo chỉ số', () {
      // Đang xem B (chỉ số 1); kéo C lên đầu thì B thành chỉ số 2.
      final p = pages(['A', 'B', 'C'], 1).reorder(2, 0);
      expect(p.codes, ['C', 'A', 'B']);
      expect(p.activeCode, 'B');
      expect(p.activeIndex, 2);
    });

    test('reorder chính trang đang xem thì nó đi theo', () {
      final p = pages(['A', 'B', 'C'], 0).reorder(0, 3);
      expect(p.codes, ['B', 'C', 'A']);
      expect(p.activeCode, 'A');
    });

    test('reorder chỉ số ngoài khoảng thì bỏ qua', () {
      final p = pages(['A', 'B']);
      expect(identical(p.reorder(5, 0), p), isTrue);
    });

    test('pruneTo giữ khung đang xem khi nó còn tồn tại', () {
      final p = pages(['A', 'X', 'B', null], 2).pruneTo({'A', 'B'});
      expect(p.codes, ['A', 'B', null]);
      expect(p.activeCode, 'B');
    });

    test('pruneTo dọn mất khung đang xem thì lùi về trang bên trái', () {
      final p = pages(['A', 'X', 'B'], 1).pruneTo({'A', 'B'});
      expect(p.activeCode, 'A');
    });

    test('pruneTo không có gì để dọn thì trả về chính nó', () {
      final p = pages(['A', null]);
      expect(identical(p.pruneTo({'A'}), p), isTrue);
    });
  });

  group('MiniGraphPins — lật trang', () {
    test('next đi vòng từ trang cuối về trang đầu', () {
      var p = pages(['A', 'B', 'C'], 1);
      p = p.next();
      expect(p.activeIndex, 2);
      p = p.next();
      expect(p.activeIndex, 0);
    });

    test('previous đi vòng từ trang đầu về trang cuối', () {
      final p = pages(['A', 'B', 'C'], 0).previous();
      expect(p.activeIndex, 2);
    });

    test('một trang hoặc rỗng thì lật không đổi gì', () {
      final one = pages(['A']);
      expect(identical(one.next(), one), isTrue);
      expect(
        identical(MiniGraphPins.empty.previous(), MiniGraphPins.empty),
        isTrue,
      );
    });

    test('select kẹp chỉ số, selectCode bỏ qua khung chưa ghim', () {
      final p = pages(['A', 'B', 'C']);
      expect(p.select(99).activeIndex, 2);
      expect(p.select(-3).activeIndex, 0);
      expect(p.selectCode('C').activeIndex, 2);
      expect(identical(p.selectCode('X'), p), isTrue);
    });
  });

  group('MiniGraphPins — encode/decode', () {
    test('encode/decode giữ thứ tự, trang null và activeIndex', () {
      final p = pages(['A', null, 'B'], 2);
      final back = MiniGraphPins.decode(p.encode(), p.activeIndex);
      expect(p.encode(), ['A', MiniGraphPins.allSentinel, 'B']);
      expect(back.codes, ['A', null, 'B']);
      expect(back.activeIndex, 2);
    });

    test('dữ liệu cũ không có activeIndex thì mở trang đầu', () {
      final back = MiniGraphPins.decode(['A', 'B']);
      expect(back.activeIndex, 0);
      expect(back.activeCode, 'A');
    });

    test('activeIndex hỏng trên đĩa bị kẹp vào khoảng hợp lệ', () {
      expect(MiniGraphPins.decode(['A', 'B'], 7).activeIndex, 1);
      expect(MiniGraphPins.decode(null, 3).activeIndex, 0);
    });

    test('SettingsService lưu và đọc lại cả trang đang xem', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.setPinnedMiniGraphs(pages(['A', 'B', 'C'], 1));
      final back = await settings.getPinnedMiniGraphs();
      expect(back.codes, ['A', 'B', 'C']);
      expect(back.activeIndex, 1);
    });
  });

  // ------------------------------------------------------------------
  // GIAO DIỆN — một cửa sổ, nhiều trang
  // ------------------------------------------------------------------

  group('MiniGraphPanel — một cửa sổ nhiều trang', () {
    final state = AppState.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      for (final code in [...state.pinnedMiniGraphs]) {
        await state.unpinMiniGraph(code);
      }
    });

    Widget app() => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 120,
              child: Column(
                children: [
                  for (final code in ['K19B', 'K20A'])
                    Draggable<MiniGraphDragData>(
                      data: MiniGraphDragData(
                        curriculumCode: code,
                        label: code,
                      ),
                      feedback: const SizedBox(width: 10, height: 10),
                      child: SizedBox(height: 40, child: Text('drag-$code')),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 300, height: 600, child: MiniGraphPanel()),
          ],
        ),
      ),
    );

    Future<void> dropOnPanel(WidgetTester tester, String code) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('drag-$code')),
      );
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(MiniGraphPanel.dropTargetKey)),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      // Hết hiệu ứng chuyển trang để trang cũ rời hẳn khỏi cây widget.
      await tester.pump(const Duration(milliseconds: 600));
    }

    String indicator(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(MiniGraphPanel.pageIndicatorKey)).data!;

    testWidgets('thả 2 khung khác nhau: đúng 1 cửa sổ, chỉ số 2/2', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      expect(
        find.text('Kéo Graph view vào đây để ghim thành một trang'),
        findsOneWidget,
      );

      await dropOnPanel(tester, 'K19B');
      // Một trang thì không có ◀ ▶ và chỉ số trang.
      expect(find.byKey(MiniGraphPanel.pageIndicatorKey), findsNothing);
      expect(find.byKey(MiniGraphPanel.previousKey), findsNothing);

      await dropOnPanel(tester, 'K20A');
      expect(find.byType(SidebarMiniGraph), findsOneWidget);
      expect(indicator(tester), '2/2');
      expect(state.activeMiniGraphCode, 'K20A');
    });

    testWidgets('bấm ◀ thì về 1/2', (tester) async {
      await tester.pumpWidget(app());
      await dropOnPanel(tester, 'K19B');
      await dropOnPanel(tester, 'K20A');

      await tester.tap(find.byKey(MiniGraphPanel.previousKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(indicator(tester), '1/2');
      expect(state.activeMiniGraphCode, 'K19B');
      expect(find.byType(SidebarMiniGraph), findsOneWidget);
    });

    testWidgets('thả lại khung đã ghim thì không tăng số trang', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await dropOnPanel(tester, 'K19B');
      await dropOnPanel(tester, 'K20A');

      await dropOnPanel(tester, 'K19B');
      expect(state.pinnedMiniGraphs, ['K19B', 'K20A']);
      expect(indicator(tester), '1/2');
      expect(find.byType(SidebarMiniGraph), findsOneWidget);
    });

    testWidgets('Ctrl+←/→ chỉ lật trang khi chuột nằm trên cửa sổ', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await dropOnPanel(tester, 'K19B');
      await dropOnPanel(tester, 'K20A');

      Future<void> ctrl(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump(const Duration(milliseconds: 600));
      }

      // Chuột ở ngoài: phím tắt không được cướp.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      await tester.pump();
      await ctrl(LogicalKeyboardKey.arrowLeft);
      expect(indicator(tester), '2/2');

      await mouse.moveTo(
        tester.getCenter(find.byKey(MiniGraphPanel.dropTargetKey)),
      );
      await tester.pump();
      await ctrl(LogicalKeyboardKey.arrowLeft);
      expect(indicator(tester), '1/2');
      // Đi vòng: trang đầu lùi tiếp thì về trang cuối.
      await ctrl(LogicalKeyboardKey.arrowLeft);
      expect(indicator(tester), '2/2');
      await ctrl(LogicalKeyboardKey.arrowRight);
      expect(indicator(tester), '1/2');
      await mouse.removePointer();
    });

    testWidgets('bấm chấm trang thì sang đúng trang đó', (tester) async {
      await tester.pumpWidget(app());
      await dropOnPanel(tester, 'K19B');
      await dropOnPanel(tester, 'K20A');

      await tester.tap(find.byKey(const ValueKey('mini-graph-dot-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(indicator(tester), '1/2');
    });
  });

  // ------------------------------------------------------------------
  // CỬA SỔ NỔI — lớp đè lên giao diện, kéo đi được
  // ------------------------------------------------------------------

  group('FloatingMiniGraphWindow — cửa sổ nổi', () {
    final state = AppState.instance;
    const area = Size(1000, 700);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await state.setMiniGraphFloating(true);
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1200, 900);
      view.devicePixelRatio = 1.0;
      addTearDown(view.reset);
    });

    Widget app() => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: area.width,
            height: area.height,
            child: const Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.black12)),
                FloatingMiniGraphWindow(area: area),
              ],
            ),
          ),
        ),
      ),
    );

    Finder window() => find.byType(FloatingMiniGraphWindow);
    Rect rectOf(WidgetTester tester) => tester.getRect(
      find.descendant(of: window(), matching: find.byType(Material)).first,
    );

    testWidgets('kéo thanh tiêu đề thì cửa sổ đi theo và được lưu lại', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      final before = rectOf(tester);

      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.titleBarKey),
        const Offset(-200, -150),
      );
      await tester.pump();

      final after = rectOf(tester);
      expect(after.left, closeTo(before.left - 200, 1));
      expect(after.top, closeTo(before.top - 150, 1));
      expect(after.size, before.size);
      expect(state.miniGraphFloatRect, isNotNull);
      expect(
        (await SettingsService.instance.getMiniGraphFloatRect()),
        hasLength(4),
      );
    });

    testWidgets('không kéo lọt ra ngoài vùng ứng dụng', (tester) async {
      await tester.pumpWidget(app());
      final stack = tester.getRect(find.byType(Stack).first);

      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.titleBarKey),
        const Offset(-5000, -5000),
      );
      await tester.pump();
      expect(rectOf(tester).topLeft, stack.topLeft);

      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.titleBarKey),
        const Offset(5000, 5000),
      );
      await tester.pump();
      expect(rectOf(tester).bottomRight, stack.bottomRight);
    });

    testWidgets('kéo góc dưới phải thì đổi cỡ, không nhỏ hơn cỡ tối thiểu', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      // Đưa về góc trên trái để còn chỗ phóng to.
      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.titleBarKey),
        const Offset(-5000, -5000),
      );
      await tester.pump();
      final before = rectOf(tester);

      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.resizeKey),
        const Offset(80, 60),
      );
      await tester.pump();
      expect(rectOf(tester).width, closeTo(before.width + 80, 1));
      expect(rectOf(tester).height, closeTo(before.height + 60, 1));

      await tester.drag(
        find.byKey(FloatingMiniGraphWindow.resizeKey),
        const Offset(-5000, -5000),
      );
      await tester.pump();
      expect(rectOf(tester).size, FloatingMiniGraphWindow.minSize);
    });

    testWidgets('thu gọn thì gỡ đồ thị khỏi cây, mở ra thì dựng lại', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      expect(find.byType(SidebarMiniGraph), findsOneWidget);

      await tester.tap(find.byKey(FloatingMiniGraphWindow.collapseKey));
      await tester.pump();
      expect(find.byType(SidebarMiniGraph), findsNothing);

      await tester.tap(find.byKey(FloatingMiniGraphWindow.collapseKey));
      await tester.pump();
      expect(find.byType(SidebarMiniGraph), findsOneWidget);
    });

    testWidgets('nút "Thu về thanh bên" tắt chế độ nổi', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(FloatingMiniGraphWindow.dockKey));
      await tester.pump();
      expect(state.miniGraphFloating, isFalse);
      expect(await SettingsService.instance.getMiniGraphFloating(), isFalse);
    });

    testWidgets('trong thanh bên có nút tách thành cửa sổ nổi', (tester) async {
      await state.setMiniGraphFloating(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 500,
              child: MiniGraphPanel(
                onPopOut: () => state.setMiniGraphFloating(true),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(MiniGraphPanel.popOutKey));
      await tester.pump();
      expect(state.miniGraphFloating, isTrue);
    });
  });
}

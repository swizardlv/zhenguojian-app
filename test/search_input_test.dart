import 'dart:async';

import 'package:duanju_app/search_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _televisionSearchHost(Widget child) => MaterialApp(
  home: Scaffold(
    body: Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA, includeRepeats: false):
            ActivateIntent(),
      },
      child: Center(child: SizedBox(width: 520, child: child)),
    ),
  ),
);

void main() {
  testWidgets(
    'search suggestions debounce, highlight, select and suppress stale results',
    (tester) async {
      final controller = TextEditingController();
      final calls = <String>[], searches = <String>[];
      final first = Completer<List<String>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SearchInput(
                controller: controller,
                hint: '搜索',
                onSearch: searches.add,
                suggestions: (query) async {
                  calls.add(query);
                  return query == '永' ? first.future : ['永世长青'];
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '永');
      await tester.pump(const Duration(milliseconds: 299));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, ['永']);
      await tester.enterText(find.byType(TextField), '永世');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      first.complete(['旧候选']);
      await tester.pumpAndSettle();
      expect(find.text('旧候选'), findsNothing);
      final item = find.byKey(const ValueKey('search-suggestion-0'));
      expect(item, findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(of: item, matching: find.byType(Text)).first,
      );
      expect(text.textSpan!.toPlainText(), '永世长青');
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(searches, ['永世长青']);
      expect(controller.text, '永世长青');
      expect(item, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('suggestion failure still allows a manual search and clearing', (
    tester,
  ) async {
    final controller = TextEditingController();
    final searches = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchInput(
            controller: controller,
            hint: '搜索',
            onSearch: searches.add,
            suggestions: (_) async => throw StateError('offline'),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '重生');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    expect(searches, ['重生']);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets(
    'TV Select submits the search field and D-pad reaches clear and search',
    (tester) async {
      final controller = TextEditingController();
      final searches = <String>[];
      var suggestionCalls = 0;
      await tester.pumpWidget(
        _televisionSearchHost(
          SearchInput(
            controller: controller,
            hint: '搜索',
            autofocus: true,
            onSearch: searches.add,
            suggestions: (_) async {
              suggestionCalls++;
              return const [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '重生');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-clear');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-field');

      await tester.enterText(find.byType(TextField), '重生');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-submit');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(searches, ['重生']);
      expect(suggestionCalls, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('TV confirm submits the highlighted autocomplete suggestion', (
    tester,
  ) async {
    final controller = TextEditingController();
    final searches = <String>[];
    final suggestionQueries = <String>[];
    await tester.pumpWidget(
      _televisionSearchHost(
        SearchInput(
          controller: controller,
          hint: '搜索',
          autofocus: true,
          onSearch: searches.add,
          suggestions: (query) async {
            suggestionQueries.add(query);
            return const ['永世长青', '永生不息'];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '永');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final first = find.byKey(const ValueKey('search-suggestion-0'));
    final second = find.byKey(const ValueKey('search-suggestion-1'));
    expect(tester.widget<ListTile>(first).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.widget<ListTile>(first).selected, isFalse);
    expect(tester.widget<ListTile>(second).selected, isTrue);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-field');

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(suggestionQueries, ['永']);
    expect(searches, ['永生不息']);
    expect(controller.text, '永生不息');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

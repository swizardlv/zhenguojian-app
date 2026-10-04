import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/catalog_filters.dart';
import 'package:duanju_app/drama_actions.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/remote_widgets.dart';
import 'package:duanju_app/saved_library.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'remote_test_helpers.dart';

class TelevisionRepository extends FixtureRepository {
  @override
  Future<DramaDetail> detail(Drama drama) async {
    detailCalls++;
    return DramaDetail(
      drama,
      List.generate(
        100,
        (index) => Episode({
          'id': '${index + 1}',
          'currentEpisode': index + 1,
          'vip': true,
        }, index + 1),
      ),
    );
  }
}

void main() {
  Future<LocalStore> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void size(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    if (key == LogicalKeyboardKey.goBack) {
      await tester.binding.handlePopRoute();
    } else {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Android TV detection falls back safely when the platform channel is unavailable',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () => messenger.setMockMethodCallHandler(AppDevice.channel, null),
      );
      messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
        expect(call.method, 'deviceInfo');
        return {'television': true, 'version': appVersion};
      });
      final detected = await AppDevice.detect();
      expect(detected.television, isTrue);
      expect(detected.version, appVersion);
      messenger.setMockMethodCallHandler(
        AppDevice.channel,
        (call) async => throw MissingPluginException(),
      );
      expect((await AppDevice.detect()).television, isFalse);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'manual interface preference overrides device detection and survives restart',
    (tester) async {
      size(tester, const Size(960, 540));
      final store = await makeStore();
      final repository = FixtureRepository();
      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store, television: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-nav-0')), findsOneWidget);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('界面模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手机 / 电脑'));
      await tester.pumpAndSettle();
      expect(store.displayMode, 'standard');
      expect(find.byKey(const ValueKey('tv-nav-0')), findsNothing);
      expect(LocalStore(store.preferences).displayMode, 'standard');
      await store.setDisplayMode('television');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-nav-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dimensions in [const Size(960, 540), const Size(1280, 720)]) {
    testWidgets(
      'TV sources, details, VIP confirmation and back retain remote focus at $dimensions',
      (tester) async {
        size(tester, dimensions);
        final store = await makeStore();
        final repository = TelevisionRepository();
        await tester.pumpWidget(
          DuanjuApp(repository: repository, store: store, television: true),
        );
        await tester.pumpAndSettle();
        if (SourceSite.values.length > 1) {
          final switcher = find.byKey(const ValueKey('source-switch'));
          final title = find
              .descendant(of: switcher, matching: find.byType(Text))
              .first;
          Focus.of(tester.element(title)).requestFocus();
          await tester.pumpAndSettle();
          await press(tester, LogicalKeyboardKey.select);
          await press(tester, LogicalKeyboardKey.arrowDown);
          await press(tester, LogicalKeyboardKey.arrowDown);
          await press(tester, LogicalKeyboardKey.select);
        }
        expect(
          repository.requests.last,
          SourceSite.values.length > 1 ? SourceSite.values[1].id : 'hongguo',
        );
        focusRemote(tester, find.byKey(ValueKey(FixtureRepository.free.id)));
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.select);
        expect(repository.detailCalls, 1);
        expect(find.byKey(const ValueKey('start-play')), findsOneWidget);
        focusRemote(tester, find.byKey(const ValueKey('episode-1')));
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.select);
        expect(find.text('这是一集 VIP 内容'), findsOneWidget);
        await press(tester, LogicalKeyboardKey.goBack);
        expect(find.text('这是一集 VIP 内容'), findsNothing);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-1');
        await press(tester, LogicalKeyboardKey.escape);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-${FixtureRepository.free.id}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'remote grid reaches unbuilt rows, partial last row and pagination without touch',
    (tester) async {
      size(tester, const Size(960, 540));
      var loaded = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteGrid(
              itemKeys: List.generate(59, (index) => '$index'),
              columns: 4,
              itemExtent: 100,
              autofocus: true,
              footer: Center(
                child: RemoteButton(label: '加载更多', onPressed: () => loaded++),
              ),
              itemBuilder: (_, index, node, onFocus) => RemoteEpisodeButton(
                number: index,
                focusNode: node,
                onFocus: onFocus,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-0');
      for (var index = 0; index < 3; index++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      for (var row = 0; row < 14; row++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-58');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);
      expect(loaded, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('episode grid initially focuses an offscreen saved episode', (
    tester,
  ) async {
    size(tester, const Size(960, 540));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteGrid(
            itemKeys: List.generate(160, (index) => '$index'),
            columns: 6,
            itemExtent: 64,
            initialIndex: 131,
            autofocus: true,
            itemBuilder: (_, index, node, onFocus) => RemoteEpisodeButton(
              number: index,
              focusNode: node,
              onFocus: onFocus,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-131');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-125');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV empty history keeps an actionable focus recovery target', (
    tester,
  ) async {
    size(tester, const Size(720, 800));
    final store = await makeStore();
    var returnToNavCalls = 0;

    await tester.pumpWidget(
      televisionHost(
        child: Scaffold(
          body: SavedLibrary(
            repository: TelevisionRepository(),
            store: store,
            history: true,
            remoteAutofocus: true,
            onExitLeft: () => returnToNavCalls++,
            onOpen: (_) {},
            onContinue: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final returnButton = find.widgetWithText(FilledButton, '返回导航');
    expect(returnButton, findsOneWidget);
    expect(Focus.of(tester.element(find.text('返回导航'))).hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(returnToNavCalls, 1);
    expect(store.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV card More action is reachable and focus returns safely', (
    tester,
  ) async {
    size(tester, const Size(720, 800));
    final itemKeys = ['history-0', 'history-1'];
    final drama = FixtureRepository.free;
    final actionFocusNode = FocusNode(debugLabel: 'history-more');
    addTearDown(actionFocusNode.dispose);
    late FocusNode firstCardFocusNode;
    late VoidCallback removeFirstFixtureItem;
    var mockActionCalls = 0;
    await tester.pumpWidget(
      televisionHost(
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 500,
              child: StatefulBuilder(
                builder: (context, setGridState) {
                  final visibleKeys = List<String>.of(itemKeys);
                  removeFirstFixtureItem = () =>
                      setGridState(() => itemKeys.removeAt(0));
                  return RemoteGrid(
                    itemKeys: visibleKeys,
                    columns: 2,
                    itemExtent: 500,
                    spacing: 0,
                    padding: EdgeInsets.zero,
                    autofocus: true,
                    itemBuilder: (context, index, node, onFocus) {
                      final itemKey = visibleKeys[index];
                      final hasAction = itemKey == 'history-0';
                      if (hasAction) firstCardFocusNode = node;
                      return DramaTile(
                        key: ValueKey('mock-history-tile-$itemKey'),
                        drama: drama,
                        repository: FixtureRepository(),
                        focusNode: node,
                        actionFocusNode: hasAction ? actionFocusNode : null,
                        onFocus: onFocus,
                        onTap: () {},
                        actions: hasAction
                            ? DramaActionButton(
                                drama: drama,
                                focusNode: actionFocusNode,
                                onPressed: () {
                                  mockActionCalls++;
                                  showDialog<void>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Mock actions'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext).pop(),
                                          child: const Text('Cancel'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(firstCardFocusNode.hasPrimaryFocus, isTrue);
    expect(find.byKey(ValueKey('drama-actions-${drama.id}')), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(actionFocusNode.hasPrimaryFocus, isTrue);
    expect(firstCardFocusNode.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(mockActionCalls, 1);
    expect(find.text('Mock actions'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.goBack);
    expect(find.text('Mock actions'), findsNothing);
    expect(actionFocusNode.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(firstCardFocusNode.hasPrimaryFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(actionFocusNode.hasPrimaryFocus, isTrue);
    expect(firstCardFocusNode.hasFocus, isTrue);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(actionFocusNode.hasPrimaryFocus, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-history-1');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-history-0');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(actionFocusNode.hasPrimaryFocus, isTrue);
    expect(firstCardFocusNode.hasFocus, isTrue);

    removeFirstFixtureItem();
    await tester.pumpAndSettle();
    expect(itemKeys, ['history-1']);
    expect(actionFocusNode.hasPrimaryFocus, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-history-1');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selected remote controls keep selection with one refined focus ring',
    (tester) async {
      const itemKeys = ['discover', 'all', 'sort'];
      const labels = ['发现', '全部', '排序与筛选'];
      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: RemoteRow(
              itemKeys: itemKeys,
              autofocus: true,
              itemBuilder: (_, index, node, onFocus) => RemoteButton(
                key: ValueKey('focus-ring-${itemKeys[index]}'),
                label: labels[index],
                selected: index < 2,
                focusNode: node,
                onFocus: onFocus,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final colors = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      BoxDecoration decorationFor(String key) {
        final target = find.byKey(ValueKey('focus-ring-$key'));
        final container = find.descendant(
          of: target,
          matching: find.byType(AnimatedContainer),
        );
        return tester.widget<AnimatedContainer>(container.first).decoration
            as BoxDecoration;
      }

      BorderSide topBorder(String key) =>
          (decorationFor(key).border! as Border).top;
      bool isSelected(String key) => tester
          .widget<RemoteButton>(find.byKey(ValueKey('focus-ring-$key')))
          .selected;
      bool hasPinkShadow(String key) =>
          decorationFor(key).boxShadow?.any(
            (shadow) => shadow.color == colors.primary.withValues(alpha: 0.16),
          ) ??
          false;
      int primaryRingCount() => itemKeys
          .where((key) => topBorder(key).color == colors.primary)
          .length;

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-row-discover',
      );
      expect(isSelected('discover'), isTrue);
      expect(isSelected('all'), isTrue);
      expect(decorationFor('discover').color, colors.primaryContainer);
      expect(topBorder('discover').color, colors.primary);
      expect(topBorder('discover').width, 2);
      expect(hasPinkShadow('discover'), isTrue);
      expect(decorationFor('all').color, colors.surfaceContainerLow);
      expect(topBorder('all').color, colors.outlineVariant);
      expect(topBorder('all').width, 1);
      expect(hasPinkShadow('all'), isFalse);
      expect(primaryRingCount(), 1);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-all');
      expect(isSelected('discover'), isTrue);
      expect(isSelected('all'), isTrue);
      expect(decorationFor('discover').color, colors.surfaceContainerLow);
      expect(topBorder('discover').color, colors.outlineVariant);
      expect(hasPinkShadow('discover'), isFalse);
      expect(decorationFor('all').color, colors.primaryContainer);
      expect(topBorder('all').color, colors.primary);
      expect(hasPinkShadow('all'), isTrue);
      expect(primaryRingCount(), 1);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-sort');
      expect(isSelected('discover'), isTrue);
      expect(isSelected('all'), isTrue);
      expect(decorationFor('discover').color, colors.surfaceContainerLow);
      expect(decorationFor('all').color, colors.surfaceContainerLow);
      expect(hasPinkShadow('discover'), isFalse);
      expect(hasPinkShadow('all'), isFalse);
      expect(decorationFor('sort').color, colors.primaryContainer);
      expect(hasPinkShadow('sort'), isTrue);
      expect(primaryRingCount(), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('selected All starts pink only while it owns focus', (
    tester,
  ) async {
    const itemKeys = ['all', 'sort'];
    const labels = ['全部', '排序与筛选'];
    await tester.pumpWidget(
      televisionHost(
        child: Scaffold(
          body: RemoteRow(
            itemKeys: itemKeys,
            initialIndex: 0,
            autofocus: true,
            itemBuilder: (_, index, node, onFocus) => RemoteButton(
              key: ValueKey('all-focus-${itemKeys[index]}'),
              label: labels[index],
              selected: index == 0,
              focusNode: node,
              onFocus: onFocus,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final colors = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    BoxDecoration decorationFor(String key) {
      final target = find.byKey(ValueKey('all-focus-$key'));
      final container = find.descendant(
        of: target,
        matching: find.byType(AnimatedContainer),
      );
      return tester.widget<AnimatedContainer>(container.first).decoration
          as BoxDecoration;
    }

    bool hasPinkShadow(String key) =>
        decorationFor(key).boxShadow?.any(
          (shadow) => shadow.color == colors.primary.withValues(alpha: 0.16),
        ) ??
        false;

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-all');
    expect(
      tester
          .widget<RemoteButton>(find.byKey(const ValueKey('all-focus-all')))
          .selected,
      isTrue,
    );
    expect(decorationFor('all').color, colors.primaryContainer);
    expect(hasPinkShadow('all'), isTrue);

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-sort');
    expect(
      tester
          .widget<RemoteButton>(find.byKey(const ValueKey('all-focus-all')))
          .selected,
      isTrue,
    );
    expect(decorationFor('all').color, colors.surfaceContainerLow);
    expect(hasPinkShadow('all'), isFalse);
    expect(decorationFor('sort').color, colors.primaryContainer);
    expect(hasPinkShadow('sort'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected Discover sidebar loses pink focus treatment in top Recommendation',
    (tester) async {
      size(tester, const Size(1280, 720));
      final navKey = GlobalKey<RemoteListState>();
      final filtersKey = GlobalKey<RemoteRowState>();
      final gridKey = GlobalKey<RemoteGridState>();
      const navKeys = ['0', '1', '2', '3'];
      const navLabels = ['发现', '追剧', '最近观看', '下载'];
      var selectedTab = 0;

      await tester.pumpWidget(
        televisionHost(
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 176,
                    child: RemoteList(
                      key: navKey,
                      itemKeys: navKeys,
                      itemExtent: 60,
                      spacing: 14,
                      padding: EdgeInsets.zero,
                      autofocus: true,
                      onExitRight: () => gridKey.currentState?.focusCurrent(),
                      itemBuilder: (_, index, node, onFocus) => RemoteButton(
                        key: ValueKey('tv-nav-${navKeys[index]}'),
                        label: navLabels[index],
                        selected: selectedTab == index,
                        focusNode: node,
                        onFocus: onFocus,
                        onPressed: () => setState(() => selectedTab = index),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        CatalogFilters(
                          key: const ValueKey('sidebar-focus-filters'),
                          categories: const [
                            CatalogCategory.all,
                            CatalogCategory('recommendations', '推荐'),
                          ],
                          category: '',
                          remoteKey: filtersKey,
                          onExitLeft: () =>
                              navKey.currentState?.focusItem('$selectedTab'),
                          onExitDown: () =>
                              gridKey.currentState?.focusCurrent(),
                          onCategory: (_) {},
                          onRetry: () {},
                        ),
                        Expanded(
                          child: RemoteGrid(
                            key: gridKey,
                            itemKeys: const ['card'],
                            columns: 1,
                            itemExtent: 76,
                            padding: EdgeInsets.zero,
                            onExitUp: () =>
                                filtersKey.currentState?.focusCurrent(),
                            itemBuilder: (_, index, node, onFocus) =>
                                RemoteButton(
                                  key: const ValueKey('sidebar-focus-card'),
                                  label: '测试视频',
                                  focusNode: node,
                                  onFocus: onFocus,
                                  onPressed: () {},
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final colors = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;

      BoxDecoration decorationFor(String key) {
        final target = find.byKey(ValueKey(key));
        final container = find.descendant(
          of: target,
          matching: find.byType(AnimatedContainer),
        );
        return tester.widget<AnimatedContainer>(container.first).decoration
            as BoxDecoration;
      }

      bool hasPinkShadow(String key) =>
          decorationFor(key).boxShadow?.any(
            (shadow) => shadow.color == colors.primary.withValues(alpha: 0.16),
          ) ??
          false;

      RemoteButton navButton(int index) => tester.widget<RemoteButton>(
        find.byKey(ValueKey('tv-nav-${navKeys[index]}')),
      );

      void expectFocusedPink(String key) {
        expect(decorationFor(key).color, colors.primaryContainer);
        expect(hasPinkShadow(key), isTrue);
      }

      void expectSelectedNeutral(String key) {
        expect(decorationFor(key).color, colors.surfaceContainerLow);
        expect(
          (decorationFor(key).border! as Border).top.color,
          colors.outlineVariant,
        );
        expect(hasPinkShadow(key), isFalse);
      }

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');
      expect(navButton(0).selected, isTrue);
      expectFocusedPink('tv-nav-0');

      // Follow the discovery path: side navigation -> grid -> top filters.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-row-recommendations',
      );
      final recommendation = tester.widget<RemoteButton>(
        find.byKey(const ValueKey('category-recommendations')),
      );
      expect(recommendation.selected, isFalse);
      expect(recommendation.focusNode!.hasPrimaryFocus, isTrue);
      expect(navButton(0).selected, isTrue);
      expectSelectedNeutral('tv-nav-0');
      expectFocusedPink('category-recommendations');

      // Left from Recommendation -> All -> selected Discover restores its ring.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');
      expect(navButton(0).selected, isTrue);
      expectFocusedPink('tv-nav-0');

      // Every remaining rail entry has the same selected/focused separation.
      for (var index = 1; index < navKeys.length; index++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-list-${navKeys[index]}',
        );
        await press(tester, LogicalKeyboardKey.select);
        expect(navButton(index).selected, isTrue);
        expectFocusedPink('tv-nav-${navKeys[index]}');
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-row-recommendations',
        );
        expect(navButton(index).selected, isTrue);
        expectSelectedNeutral('tv-nav-${navKeys[index]}');
        expectFocusedPink('category-recommendations');
        await press(tester, LogicalKeyboardKey.arrowLeft);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-list-${navKeys[index]}',
        );
        expectFocusedPink('tv-nav-${navKeys[index]}');
      }
      expect(navButton(0).selected, isFalse);
      expect(decorationFor('tv-nav-0').color, Colors.transparent);
      expect(hasPinkShadow('tv-nav-0'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discovery focus crosses navigation, categories and grid without traps',
    (tester) async {
      size(tester, const Size(640, 480));
      final navKey = GlobalKey<RemoteListState>();
      final filtersKey = GlobalKey<RemoteRowState>();
      final gridKey = GlobalKey<RemoteGridState>();
      final gridController = ScrollController();
      addTearDown(gridController.dispose);
      var selectedCategory = '';
      const navKeys = ['0', '1', '2', '3'];
      const navLabels = ['发现', '追剧', '最近观看', '下载'];
      final categories = [
        CatalogCategory.all,
        for (var index = 0; index < 11; index++)
          CatalogCategory('channel-$index', '分类${index + 1}'),
      ];
      final allCategory = find.byKey(const ValueKey('category-'));
      final filterViewport = find.descendant(
        of: find.byKey(const ValueKey('filters-harness')),
        matching: find.byType(SingleChildScrollView),
      );
      Rect categoryViewportRect() => tester.getRect(filterViewport.first);
      Rect gridViewportRect() => tester.getRect(
        find.descendant(
          of: find.byKey(gridKey),
          matching: find.byType(CustomScrollView),
        ),
      );
      Rect cardRect(int index) =>
          tester.getRect(find.byKey(ValueKey('harness-card-$index')));
      Rect allCategoryRect() => tester.getRect(allCategory);
      bool isFullyVisible(Rect item, Rect viewport) =>
          item.left >= viewport.left &&
          item.right <= viewport.right &&
          item.top >= viewport.top &&
          item.bottom <= viewport.bottom;

      await tester.pumpWidget(
        televisionHost(
          child: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 144,
                  child: RemoteList(
                    key: navKey,
                    itemKeys: navKeys,
                    itemExtent: 52,
                    spacing: 6,
                    padding: EdgeInsets.zero,
                    autofocus: true,
                    onExitRight: () => gridKey.currentState?.focusCurrent(),
                    itemBuilder: (_, index, node, onFocus) => RemoteButton(
                      key: ValueKey('harness-nav-${navKeys[index]}'),
                      label: navLabels[index],
                      selected: index == 0,
                      focusNode: node,
                      onFocus: onFocus,
                      onPressed: () {},
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      StatefulBuilder(
                        builder: (context, setState) => CatalogFilters(
                          key: const ValueKey('filters-harness'),
                          categories: categories,
                          category: selectedCategory,
                          remoteKey: filtersKey,
                          onExitLeft: () => navKey.currentState?.focusItem('0'),
                          onExitDown: () =>
                              gridKey.currentState?.focusCurrent(),
                          onCategory: (category) =>
                              setState(() => selectedCategory = category),
                          onRetry: () {},
                        ),
                      ),
                      Expanded(
                        child: RemoteGrid(
                          key: gridKey,
                          controller: gridController,
                          itemKeys: List.generate(24, (index) => 'card-$index'),
                          columns: 3,
                          itemExtent: 76,
                          spacing: 6,
                          padding: EdgeInsets.zero,
                          onExitUp: () =>
                              filtersKey.currentState?.focusCurrent(),
                          onExitLeft: () => navKey.currentState?.focusItem('0'),
                          itemBuilder: (_, index, node, onFocus) =>
                              RemoteButton(
                                key: ValueKey('harness-card-$index'),
                                label: '短剧${index + 1}',
                                focusNode: node,
                                onFocus: onFocus,
                                onPressed: () {},
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');

      for (var index = 0; index < navKeys.length - 1; index++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-3');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-0');
      final categoryViewport = categoryViewportRect();
      expect(
        gridViewportRect().top,
        greaterThanOrEqualTo(categoryViewport.bottom),
      );
      expect(isFullyVisible(cardRect(0), gridViewportRect()), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-3');
      expect(isFullyVisible(cardRect(3), gridViewportRect()), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-0');
      expect(isFullyVisible(cardRect(0), gridViewportRect()), isTrue);

      for (var row = 1; row <= 6; row++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        final index = row * 3;
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-card-$index',
        );
        expect(
          isFullyVisible(cardRect(index), gridViewportRect()),
          isTrue,
          reason:
              'focused row $row must be revealed beneath category navigation',
        );
      }
      expect(
        gridController.offset,
        greaterThan(76),
        reason:
            'the first row should roll fully above the viewport after moving down',
      );

      for (var row = 5; row >= 0; row--) {
        await press(tester, LogicalKeyboardKey.arrowUp);
        final index = row * 3;
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'remote-card-$index',
          reason:
              'Up must return through grid rows before leaving for categories',
        );
        expect(
          isFullyVisible(cardRect(index), gridViewportRect()),
          isTrue,
          reason: 'scrolled-off row $row must be revealed when focus returns',
        );
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-0');
      expect(isFullyVisible(cardRect(0), gridViewportRect()), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');
      expect(isFullyVisible(allCategoryRect(), categoryViewportRect()), isTrue);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-row-channel-0',
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(selectedCategory, 'channel-0');
      for (var index = 1; index < categories.length; index++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'remote-row-channel-10',
      );
      final viewportAfterScroll = categoryViewportRect();
      final allAfterScroll = allCategoryRect();
      expect(viewportAfterScroll.overlaps(allAfterScroll), isFalse);

      for (var index = 1; index < categories.length; index++) {
        await press(tester, LogicalKeyboardKey.arrowLeft);
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');
      final returnedAll = allCategoryRect();
      final returnedViewport = categoryViewportRect();
      expect(
        isFullyVisible(returnedAll, returnedViewport),
        isTrue,
        reason: 'All rect=$returnedAll viewport=$returnedViewport',
      );
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-0');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');
      expect(isFullyVisible(allCategoryRect(), categoryViewportRect()), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-card-0');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TV category edge reaches retry and trailing VIP filter', (
    tester,
  ) async {
    size(tester, const Size(1280, 800));
    final filtersKey = GlobalKey<RemoteRowState>();
    final gridKey = GlobalKey<RemoteGridState>();
    final vipFocus = FocusNode(debugLabel: 'vip-filter');
    addTearDown(vipFocus.dispose);
    var retries = 0;
    var vipToggles = 0;

    await tester.pumpWidget(
      televisionHost(
        child: Scaffold(
          body: Column(
            children: [
              CatalogFilters(
                categories: const [
                  CatalogCategory.all,
                  CatalogCategory('human', '真人剧'),
                ],
                category: '',
                error: '分类加载失败',
                remoteKey: filtersKey,
                remoteAutofocus: true,
                trailingFocusNode: vipFocus,
                trailing: IconButton(
                  key: const ValueKey('vip-filter-button'),
                  focusNode: vipFocus,
                  tooltip: 'VIP 筛选',
                  onPressed: () => vipToggles++,
                  icon: const Icon(Icons.filter_alt),
                ),
                onCategory: (_) {},
                onRetry: () => retries++,
                onExitDown: () => gridKey.currentState?.focusCurrent(),
              ),
              Expanded(
                child: RemoteGrid(
                  key: gridKey,
                  itemKeys: const ['first-card', 'second-card'],
                  columns: 2,
                  itemExtent: 100,
                  padding: EdgeInsets.zero,
                  onExitUp: () => filtersKey.currentState?.focusCurrent(),
                  itemBuilder: (_, index, node, onFocus) => RemoteButton(
                    key: ValueKey('filter-grid-$index'),
                    label: '结果 $index',
                    focusNode: node,
                    onFocus: onFocus,
                    onPressed: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-');

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-human');
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'catalog-filter-retry',
    );
    await press(tester, LogicalKeyboardKey.select);
    expect(retries, 1);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'vip-filter');
    await press(tester, LogicalKeyboardKey.select);
    expect(vipToggles, 1);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'catalog-filter-retry',
    );
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-row-human');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-first-card');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

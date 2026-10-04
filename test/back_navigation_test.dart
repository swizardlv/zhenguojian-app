import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/recommendations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'remote_test_helpers.dart';

class EmptyHomeRepository extends FixtureRepository {
  final recommendationCalls = <String>[];
  @override
  bool get supportsDownloads => true;
  @override
  Future<List<DownloadJob>> downloads() async => [];

  @override
  Future<CatalogPage> recommendations(
    String genre, {
    bool more = false,
    bool force = false,
  }) async {
    recommendationCalls.add(genre);
    return CatalogPage([]);
  }

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage([]);

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage([]);

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';
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

  Future<void> pressRemoteBackKey(WidgetTester tester) async {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Recent Viewed Back releases search focus before directional navigation',
    (tester) async {
      size(tester, const Size(1280, 720));
      final store = await makeStore();
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');
      await press(tester, LogicalKeyboardKey.select);

      final search = find.byKey(const ValueKey('history-search'));
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-search');

      await pressRemoteBackKey(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-1');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');

      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-search');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-1');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');

      await press(tester, LogicalKeyboardKey.goBack);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-0');
      expect(find.text('退出应用？'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Favorites search Back releases its field before leaving the tab',
    (tester) async {
      size(tester, const Size(1280, 720));
      final store = await makeStore();
      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-1');
      await press(tester, LogicalKeyboardKey.select);
      final search = find.byKey(const ValueKey('favorites-search'));
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'favorites-search',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-1');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-2');
      expect(find.text('退出应用？'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Downloads search Back releases its field before returning to Discovery',
    (tester) async {
      size(tester, const Size(390, 844));
      final store = await makeStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载').last);
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('downloads-search'));
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'downloads-search',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('downloads-search'),
      );
      expect(find.text('退出应用？'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(find.text('退出应用？'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Back from embedded recommendations returns to Discovery', (
    tester,
  ) async {
    size(tester, const Size(1280, 720));
    final store = await makeStore();
    final repository = EmptyHomeRepository();
    await tester.pumpWidget(
      televisionHost(
        child: HomeScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
    final recommendations = find.byKey(
      const ValueKey('category-app:recommendations'),
    );
    expect(recommendations, findsOneWidget);
    await tester.tap(recommendations);
    await tester.pumpAndSettle();
    expect(find.byType(RecommendationsScreen), findsOneWidget);
    expect(repository.recommendationCalls, ['short_play']);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RecommendationsScreen), findsNothing);
    expect(
      find.byKey(const ValueKey('category-app:recommendations')),
      findsOneWidget,
    );
    expect(find.text('退出应用？'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inner route and overlay return first; root exit requires confirmation',
    (tester) async {
      size(tester, const Size(480, 800));
      final store = await makeStore();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var exitCalls = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();

      final routeDone = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('内页')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await routeDone;
      expect(find.text('内页'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('退出应用？'), findsNothing);
      expect(exitCalls, 0);

      final homeContext = tester.element(find.byType(HomeScreen));
      final overlayDone = showDialog<void>(
        context: homeContext,
        builder: (_) => const AlertDialog(title: Text('测试弹层')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await overlayDone;
      expect(find.text('测试弹层'), findsNothing);
      expect(find.text('退出应用？'), findsNothing);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('退出应用？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '退出'));
      await tester.pumpAndSettle();
      expect(exitCalls, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mobile root system Back keeps the exit prompt visible and Cancel leaves keyboard usable',
    (tester) async {
      size(tester, const Size(480, 800));
      final store = await makeStore();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var exitCalls = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.text('退出应用？'), findsOneWidget);
      }
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(exitCalls, 0);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.text('退出应用？'), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(exitCalls, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus,
        isNot(same(FocusManager.instance.rootScope)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remote Back plus overlapping system pop cannot dismiss root confirmation',
    (tester) async {
      size(tester, const Size(1280, 720));
      final store = await makeStore();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var exitCalls = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls++;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        televisionHost(
          child: HomeScreen(repository: EmptyHomeRepository(), store: store),
        ),
      );
      await tester.pumpAndSettle();
      await pressRemoteBackKey(tester);
      expect(find.text('退出应用？'), findsOneWidget);

      // Some remotes deliver both a logical Back key and a platform popRoute.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.text('退出应用？'), findsOneWidget);
      }
      expect(exitCalls, 0);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.text('退出应用？'), findsNothing);
      expect(exitCalls, 0);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'remote-list-1');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('退出应用？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '退出'));
      await tester.pumpAndSettle();
      expect(exitCalls, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('退出应用？'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'remote_test_helpers.dart';

class VipOnlyStore extends LocalStore {
  VipOnlyStore(super.preferences);

  @override
  List<SourceSite> get sources => [SourceSite.byId('huangdou')];

  @override
  String get source => 'huangdou';

  @override
  bool allowsSource(String source) => source == 'huangdou';

  @override
  bool get hideVip => true;
}

class PartialVipRepository extends FixtureRepository {
  static const vipDrama = Drama(
    id: 'huangdou:vip-only',
    source: 'huangdou',
    title: '会员测试剧',
    vip: true,
  );

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => const [CatalogCategory.all];

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage([vipDrama], warning: '同组另一个站源暂不可用');
}

void main() {
  testWidgets('local VIP filtering keeps partial-source warning visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = VipOnlyStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);

    await tester.pumpWidget(
      televisionHost(
        child: HomeScreen(repository: PartialVipRepository(), store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有找到匹配的短剧'), findsOneWidget);
    expect(find.textContaining('同组另一个站源暂不可用'), findsOneWidget);
    expect(find.textContaining('显示 VIP 内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

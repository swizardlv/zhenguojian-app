import 'package:duanju_app/catalog_browser.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class QueryCaptureRepository extends FixtureRepository {
  static const localMatch = Drama(
    id: 'huangdou:local-match',
    source: 'huangdou',
    title: 'needle 本地缓存',
  );
  static const localNonMatch = Drama(
    id: 'huangdou:local-other',
    source: 'huangdou',
    title: '不相关缓存',
  );
  static const onlineMatch = Drama(
    id: 'hongguo:online-match',
    source: 'hongguo',
    title: 'needle 在线结果',
  );

  final calls = <({String source, String query})>[];

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    calls.add((source: source, query: query));
    if (query.isEmpty && source == 'huangdou') {
      return CatalogPage([localMatch, localNonMatch]);
    }
    if (query.isNotEmpty && source == 'hongguo') {
      return CatalogPage([onlineMatch]);
    }
    return CatalogPage([]);
  }
}

void main() {
  test(
    'mixed-source query targets online-search sources and locally matches loaded cache',
    () async {
      final repository = QueryCaptureRepository();
      final browser = CatalogBrowser(repository);
      final group = SourceGroup('all', '全部站源', [
        SourceSite.hongguo,
        SourceSite.byId('huangdou'),
      ]);

      await browser.load(group);
      final result = await browser.load(group, query: ' needle ');

      expect(
        repository.calls
            .where((call) => call.query == 'needle')
            .map((call) => call.source),
        ['hongguo'],
      );
      expect(result.items.map((item) => item.id).toSet(), {
        QueryCaptureRepository.localMatch.id,
        QueryCaptureRepository.onlineMatch.id,
      });
      expect(
        result.items.any(
          (item) => item.id == QueryCaptureRepository.localNonMatch.id,
        ),
        isFalse,
      );
    },
  );
}

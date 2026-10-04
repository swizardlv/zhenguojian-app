import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/catalog_filters.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget phoneHost({required Widget child}) => MaterialApp(
  theme: AppTheme.light,
  builder: (_, child) =>
      AppLayout(television: false, child: FocusTraversalGroup(child: child!)),
  home: child,
);

void main() {
  testWidgets(
    'phone catalog keeps selected All neutral until focus returns to it',
    (tester) async {
      var selectedCategory = '';
      final selectedCalls = <String>[];
      const categories = [
        CatalogCategory.all,
        CatalogCategory('recommendations', '推荐'),
        CatalogCategory('human', '真人剧'),
      ];

      await tester.pumpWidget(
        phoneHost(
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CatalogFilters(
                categories: categories,
                category: selectedCategory,
                onCategory: (category) {
                  selectedCalls.add(category);
                  setState(() => selectedCategory = category);
                },
                onRetry: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final colors = Theme.of(
        tester.element(find.byType(CatalogFilters)),
      ).colorScheme;
      Finder chip(String id) => find.byKey(ValueKey('category-$id'));
      ChoiceChip widgetFor(String id) => tester.widget<ChoiceChip>(chip(id));
      FocusNode focusFor(String id) => widgetFor(id).focusNode!;
      Color fillFor(String id) {
        final ink = find.descendant(of: chip(id), matching: find.byType(Ink));
        expect(ink, findsOneWidget);
        final decoration = tester.widget<Ink>(ink).decoration;
        expect(decoration, isA<ShapeDecoration>());
        return (decoration! as ShapeDecoration).color ?? Colors.transparent;
      }

      final allFocus = focusFor('');
      final recommendationsFocus = focusFor('recommendations');
      expect(widgetFor('').selected, isTrue);
      expect(widgetFor('recommendations').selected, isFalse);
      expect(allFocus.hasPrimaryFocus, isFalse);
      expect(fillFor(''), colors.surfaceContainerLow);

      recommendationsFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(recommendationsFocus.hasPrimaryFocus, isTrue);
      expect(allFocus.hasPrimaryFocus, isFalse);
      final recommendationsInkWell = tester.widget<InkWell>(
        find
            .descendant(
              of: chip('recommendations'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(recommendationsInkWell.focusNode, same(recommendationsFocus));
      expect(widgetFor('').selected, isTrue);
      expect(widgetFor('recommendations').selected, isFalse);
      expect(fillFor(''), colors.surfaceContainerLow);
      expect(fillFor('recommendations'), isNot(colors.secondaryContainer));
      expect(selectedCalls, isEmpty);

      allFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(allFocus.hasPrimaryFocus, isTrue);
      expect(widgetFor('').selected, isTrue);
      expect(fillFor(''), colors.secondaryContainer);

      await tester.tap(chip('recommendations'));
      await tester.pumpAndSettle();
      expect(selectedCalls, ['recommendations']);
      expect(selectedCategory, 'recommendations');
      expect(widgetFor('').selected, isFalse);
      expect(widgetFor('recommendations').selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

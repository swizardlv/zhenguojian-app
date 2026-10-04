import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'models.dart';
import 'remote_widgets.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.trailing,
    this.trailingFocusNode,
    this.remoteKey,
    this.remoteAutofocus = false,
    this.onExitLeft,
    this.onExitRight,
    this.onExitUp,
    this.onExitDown,
  });

  final List<CatalogCategory> categories;
  final String category;
  final String? error;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final Widget? trailing;
  final FocusNode? trailingFocusNode;
  final GlobalKey<RemoteRowState>? remoteKey;
  final bool remoteAutofocus;
  final VoidCallback? onExitLeft;
  final VoidCallback? onExitRight;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _anchors = <String, GlobalKey>{};
  final _categoryFocusNodes = <String, FocusNode>{};
  final _retryFocusNode = FocusNode(debugLabel: 'catalog-filter-retry');

  FocusNode _focusNodeForCategory(String id) =>
      _categoryFocusNodes.putIfAbsent(id, () {
        final node = FocusNode(debugLabel: 'catalog-category-$id');
        node.addListener(_onCategoryFocusChanged);
        return node;
      });

  void _onCategoryFocusChanged() {
    if (mounted) setState(() {});
  }

  void _removeStaleCategoryFocusNodes() {
    final categoryIds = widget.categories.map((entry) => entry.id).toSet();
    for (final entry in _categoryFocusNodes.entries.toList()) {
      if (!categoryIds.contains(entry.key)) {
        entry.value.removeListener(_onCategoryFocusChanged);
        entry.value.dispose();
        _categoryFocusNodes.remove(entry.key);
      }
    }
  }

  ChoiceChip _phoneCategoryChip(BuildContext context, CatalogCategory entry) {
    final focusNode = _focusNodeForCategory(entry.id);
    final selected = entry.id == widget.category;
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      key: ValueKey('category-${entry.id}'),
      label: Text(entry.name),
      focusNode: focusNode,
      selected: selected,
      selectedColor: selected && !focusNode.hasPrimaryFocus
          ? colors.surfaceContainerLow
          : null,
      showCheckmark: false,
      onSelected: (_) => widget.onCategory(entry.id),
    );
  }

  @override
  void initState() {
    super.initState();
    _retryFocusNode.onKeyEvent = (node, event) =>
        _onAuxiliaryKey(node, event, trailing: false);
    widget.trailingFocusNode?.onKeyEvent = (node, event) =>
        _onAuxiliaryKey(node, event, trailing: true);
  }

  @override
  void dispose() {
    widget.trailingFocusNode?.onKeyEvent = null;
    for (final node in _categoryFocusNodes.values) {
      node.removeListener(_onCategoryFocusChanged);
      node.dispose();
    }
    _categoryFocusNodes.clear();
    _retryFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onAuxiliaryKey(
    FocusNode node,
    KeyEvent event, {
    required bool trailing,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (trailing && widget.error != null) {
        _retryFocusNode.requestFocus();
      } else {
        widget.remoteKey?.currentState?.focusCurrent();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!trailing && widget.trailingFocusNode != null) {
        widget.trailingFocusNode!.requestFocus();
        return KeyEventResult.handled;
      }
      if (widget.onExitRight != null) {
        widget.onExitRight!();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onExitUp != null) {
      widget.onExitUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.onExitDown != null) {
      widget.onExitDown!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _exitCategoryRowRight() {
    if (widget.error != null) {
      _retryFocusNode.requestFocus();
    } else if (widget.trailingFocusNode != null) {
      widget.trailingFocusNode!.requestFocus();
    } else {
      widget.onExitRight?.call();
    }
  }

  int get _selectedIndex {
    final index = widget.categories.indexWhere(
      (entry) => entry.id == widget.category,
    );
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant CatalogFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    _removeStaleCategoryFocusNodes();
    if (oldWidget.trailingFocusNode != widget.trailingFocusNode) {
      oldWidget.trailingFocusNode?.onKeyEvent = null;
      widget.trailingFocusNode?.onKeyEvent = (node, event) =>
          _onAuxiliaryKey(node, event, trailing: true);
    }
    if (oldWidget.category != widget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anchor = _anchors[widget.category]?.currentContext;
        if (mounted && anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            alignment: .4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    return SizedBox(
      height: television
          ? 64
          : max(52, MediaQuery.textScalerOf(context).scale(14) + 28),
      child: Row(
        children: [
          Expanded(
            child: television
                ? RemoteRow(
                    key: widget.remoteKey,
                    itemKeys: [for (final entry in widget.categories) entry.id],
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    initialIndex: _selectedIndex,
                    autofocus: widget.remoteAutofocus,
                    onExitLeft: widget.onExitLeft,
                    onExitRight: _exitCategoryRowRight,
                    onExitUp: widget.onExitUp,
                    onExitDown: widget.onExitDown,
                    itemBuilder: (_, index, node, onFocus) {
                      final entry = widget.categories[index];
                      return KeyedSubtree(
                        key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                        child: RemoteButton(
                          key: ValueKey('category-${entry.id}'),
                          label: entry.name,
                          selected: entry.id == widget.category,
                          focusNode: node,
                          onFocus: onFocus,
                          onPressed: () => widget.onCategory(entry.id),
                        ),
                      );
                    },
                  )
                : SingleChildScrollView(
                    key: const ValueKey('catalog-categories'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final entry in widget.categories)
                          Padding(
                            key: _anchors.putIfAbsent(entry.id, GlobalKey.new),
                            padding: const EdgeInsets.only(right: 6),
                            child: _phoneCategoryChip(context, entry),
                          ),
                      ],
                    ),
                  ),
          ),
          if (widget.error != null)
            IconButton(
              focusNode: television ? _retryFocusNode : null,
              tooltip: widget.error,
              onPressed: widget.onRetry,
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

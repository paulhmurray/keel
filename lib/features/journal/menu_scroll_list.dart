import 'package:flutter/material.dart';

/// The scrolling body of the editor's pop-up menus (/ commands, @ people,
/// # glossary). Keyboard selection moves the highlight; this keeps the
/// highlighted row on screen as it moves (including wrap-around), and
/// shows a scrollbar so the mouse wheel and drag work too.
class MenuScrollList extends StatefulWidget {
  final int selectedIndex;
  final List<Widget> children;

  const MenuScrollList({
    super.key,
    required this.selectedIndex,
    required this.children,
  });

  @override
  State<MenuScrollList> createState() => _MenuScrollListState();
}

class _MenuScrollListState extends State<MenuScrollList> {
  final _scroll = ScrollController();
  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _reveal(down: true);
  }

  @override
  void didUpdateWidget(MenuScrollList old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex ||
        old.children.length != widget.children.length) {
      _reveal(down: widget.selectedIndex >= old.selectedIndex);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal({required bool down}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.children.isEmpty) return;
      final i = widget.selectedIndex.clamp(0, widget.children.length - 1);
      final ctx = i < _keys.length ? _keys[i].currentContext : null;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 100),
        alignmentPolicy: down
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    while (_keys.length < widget.children.length) {
      _keys.add(GlobalKey());
    }
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              KeyedSubtree(key: _keys[i], child: widget.children[i]),
          ],
        ),
      ),
    );
  }
}

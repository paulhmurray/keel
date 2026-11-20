import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../core/journal/journal_parser.dart';
import '../../shared/theme/keel_colors.dart';
import 'journal_delta_item.dart';

class JournalDeltaPanel extends StatefulWidget {
  final List<DetectedDelta> deltas;
  final VoidCallback onConfirmAll;
  final VoidCallback onDismiss;

  const JournalDeltaPanel({
    super.key,
    required this.deltas,
    required this.onConfirmAll,
    required this.onDismiss,
  });

  @override
  State<JournalDeltaPanel> createState() => _JournalDeltaPanelState();
}

class _JournalDeltaPanelState extends State<JournalDeltaPanel> {
  int _activeIndex = 0;
  bool _editingActive = false;
  late FocusNode _focusNode;
  final _scroll = ScrollController();
  // One stable key per delta (not one key moved between items, which
  // would carry an open edit form's state to the wrong item).
  final Map<DetectedDelta, GlobalKey> _itemKeys = {};
  GlobalKey _keyFor(DetectedDelta d) =>
      _itemKeys.putIfAbsent(d, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// After the active item changes, scrolls just enough to show it: the
  /// next change below the fold slides up into view as the bottom one is
  /// actioned, and stepping back up reveals items above. An item taller
  /// than the pane shows from its top.
  void _revealActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pending = _pending;
      if (pending.isEmpty) return;
      final active = pending[_activeIndex.clamp(0, pending.length - 1)];
      final box = _itemKeys[active]?.currentContext?.findRenderObject();
      if (box == null || !box.attached) return;
      final target = revealOffset(
        current: _scroll.position.pixels,
        alignTop: RenderAbstractViewport.of(
          box,
        ).getOffsetToReveal(box, 0).offset,
        alignBottom: RenderAbstractViewport.of(
          box,
        ).getOffsetToReveal(box, 1).offset,
      );
      if (target == null) return;
      final pos = _scroll.position;
      _scroll.animateTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  List<DetectedDelta> get _pending =>
      widget.deltas.where((d) => !d.confirmed && !d.ignored).toList();

  /// Returns keyboard focus to the panel after editing ends, and keeps
  /// the (possibly new) active item on screen.
  void _reclaimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _revealActive();
  }

  void _confirmActive() {
    setState(() {
      _editingActive = false;
      final pending = _pending;
      if (pending.isNotEmpty && _activeIndex < pending.length) {
        pending[_activeIndex].confirmed = true;
        if (_activeIndex >= pending.length - 1 && _activeIndex > 0) {
          _activeIndex = pending.length - 2;
        }
        if (_activeIndex < 0) _activeIndex = 0;
      }
    });
    _reclaimFocus();
  }

  void _ignoreActive() {
    setState(() {
      _editingActive = false;
      final pending = _pending;
      if (pending.isNotEmpty && _activeIndex < pending.length) {
        pending[_activeIndex].ignored = true;
        if (_activeIndex >= pending.length - 1 && _activeIndex > 0) {
          _activeIndex = pending.length - 2;
        }
        if (_activeIndex < 0) _activeIndex = 0;
      }
    });
    _reclaimFocus();
  }

  void _cancelEdit() {
    setState(() => _editingActive = false);
    _reclaimFocus();
  }

  /// Puts a confirmed/ignored item back into the pending pile and makes
  /// it active. Decisions here are freely reversible until Confirm All
  /// (or dismiss) commits them.
  void _reopen(DetectedDelta delta) {
    setState(() {
      delta.confirmed = false;
      delta.ignored = false;
      _editingActive = false;
      final idx = _pending.indexOf(delta);
      if (idx >= 0) _activeIndex = idx;
    });
    _reclaimFocus();
  }

  void _nextItem() {
    setState(() {
      _editingActive = false;
      final pending = _pending;
      if (_activeIndex < pending.length - 1) _activeIndex++;
    });
    _reclaimFocus();
  }

  void _prevItem() {
    setState(() {
      _editingActive = false;
      if (_activeIndex > 0) _activeIndex--;
    });
    _reclaimFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isMetaOrCtrl =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

    // While an edit form is open, plain keystrokes are the user TYPING
    // into its fields — they bubble up here, so reacting to them is how
    // typing a name ending in 'y' used to confirm the item mid-edit.
    // Only Escape (cancel the edit) is handled; everything else belongs
    // to the text fields.
    if (_editingActive) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyY ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (isMetaOrCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
        widget.onConfirmAll();
        return KeyEventResult.handled;
      }
      if (!isMetaOrCtrl) {
        _confirmActive();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      _ignoreActive();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      if (_pending.isNotEmpty) {
        setState(() => _editingActive = true);
        _revealActive(); // the edit form makes the item taller
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isShift) {
        _prevItem();
      } else {
        _nextItem();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final allDeltas = widget.deltas;
    final pendingCount = _pending.length;
    final confirmedCount = allDeltas.where((d) => d.confirmed).length;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Container(
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border(left: BorderSide(color: KColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: KColors.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: KColors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'CHANGES DETECTED',
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                    ),
                  ),
                  const Spacer(),
                  if (confirmedCount > 0)
                    Flexible(
                      child: Text(
                        '$confirmedCount confirmed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: KColors.phosphor, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),

            if (allDeltas.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 32,
                        color: KColors.textMuted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No items detected.',
                        style: TextStyle(color: KColors.textDim, fontSize: 12),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Entry saved.',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                // Not a lazy ListView: every item must be laid out so the
                // active one can be scrolled to, however far below.
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: allDeltas.asMap().entries.map((e) {
                      final pending = _pending;
                      final pendingIdx = pending.indexOf(e.value);
                      final isActive = pendingIdx == _activeIndex;
                      return JournalDeltaItemWidget(
                        key: _keyFor(e.value),
                        delta: e.value,
                        isActive: isActive,
                        isEditing: isActive && _editingActive,
                        onConfirm: _confirmActive,
                        onIgnore: _ignoreActive,
                        onEdit: () {
                          setState(() => _editingActive = true);
                          _revealActive();
                        },
                        onCancelEdit: _cancelEdit,
                        onReopen: () => _reopen(e.value),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: KColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _KeyHintRow(
                    hints: [
                      _KeyHintData('Y', 'confirm'),
                      _KeyHintData('E', 'edit'),
                      _KeyHintData('N', 'ignore'),
                      _KeyHintData('Tab', 'next'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: pendingCount > 0
                              ? widget.onConfirmAll
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KColors.phosDim,
                            foregroundColor: KColors.phosphor,
                            side: BorderSide(
                              color: KColors.phosphor,
                              width: 0.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Cmd+Enter: Confirm All',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: widget.onDismiss,
                    child: Text(
                      'Esc — dismiss (unconfirmed items left pending)',
                      style: TextStyle(color: KColors.textMuted, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyHintData {
  final String keyLabel;
  final String actionLabel;
  const _KeyHintData(this.keyLabel, this.actionLabel);
}

class _KeyHintRow extends StatelessWidget {
  final List<_KeyHintData> hints;
  const _KeyHintRow({required this.hints});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < hints.length; i++) {
      final h = hints[i];
      widgets.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: KColors.border2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                h.keyLabel,
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              h.actionLabel,
              style: TextStyle(color: KColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      );
      if (i < hints.length - 1) {
        widgets.add(const SizedBox(width: 12));
      }
    }
    return Row(children: widgets);
  }
}

/// Where to scroll so an item is fully visible, or null if it already is.
/// [alignTop] / [alignBottom] are the offsets that put the item's top at
/// the viewport top / its bottom at the viewport bottom. Pure.
@visibleForTesting
double? revealOffset({
  required double current,
  required double alignTop,
  required double alignBottom,
}) {
  if (current > alignTop) return alignTop; // above the fold: show its top
  if (current < alignBottom) {
    // Below: bring its bottom up — unless it's taller than the pane, in
    // which case show its top.
    return alignBottom < alignTop ? alignBottom : alignTop;
  }
  return null;
}

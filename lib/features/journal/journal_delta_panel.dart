import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<DetectedDelta> get _pending =>
      widget.deltas.where((d) => !d.confirmed && !d.ignored).toList();

  /// Returns keyboard focus to the panel after editing ends.
  void _reclaimFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
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
    final isMetaOrCtrl = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;

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
      if (!_editingActive) {
        _ignoreActive();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      if (!_editingActive && _pending.isNotEmpty) {
        setState(() => _editingActive = true);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (!_editingActive) {
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        if (isShift) { _prevItem(); } else { _nextItem(); }
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_editingActive) {
        _cancelEdit();
        return KeyEventResult.handled;
      }
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
        decoration: const BoxDecoration(
          color: KColors.surface,
          border: Border(left: BorderSide(color: KColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: KColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: KColors.amber),
                  const SizedBox(width: 8),
                  const Text(
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
                    Text(
                      '$confirmedCount confirmed',
                      style: const TextStyle(
                          color: KColors.phosphor, fontSize: 10),
                    ),
                ],
              ),
            ),

            if (allDeltas.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 32, color: KColors.textMuted),
                      SizedBox(height: 8),
                      Text('No items detected.',
                          style: TextStyle(color: KColors.textDim, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('Entry saved.',
                          style: TextStyle(color: KColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: allDeltas.asMap().entries.map((e) {
                    final pending = _pending;
                    final pendingIdx = pending.indexOf(e.value);
                    final isActive = pendingIdx == _activeIndex;
                    return JournalDeltaItemWidget(
                      delta: e.value,
                      isActive: isActive,
                      isEditing: isActive && _editingActive,
                      onConfirm: _confirmActive,
                      onIgnore: _ignoreActive,
                      onEdit: () => setState(() => _editingActive = true),
                      onCancelEdit: _cancelEdit,
                    );
                  }).toList(),
                ),
              ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: KColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _KeyHintRow(hints: [
                    _KeyHintData('Y', 'confirm'),
                    _KeyHintData('E', 'edit'),
                    _KeyHintData('N', 'ignore'),
                    _KeyHintData('Tab', 'next'),
                  ]),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: pendingCount > 0 ? widget.onConfirmAll : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KColors.phosDim,
                            foregroundColor: KColors.phosphor,
                            side: const BorderSide(color: KColors.phosphor, width: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text(
                            'Cmd+Enter: Confirm All',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: widget.onDismiss,
                    child: const Text(
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
      widgets.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: KColors.border2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(h.keyLabel,
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          Text(h.actionLabel,
              style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
        ],
      ));
      if (i < hints.length - 1) {
        widgets.add(const SizedBox(width: 12));
      }
    }
    return Row(children: widgets);
  }
}

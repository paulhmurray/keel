import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/keel_colors.dart';

/// Floating input that appears when the user presses `N` on Canvas.
///
/// Flow:
///   - Type a title.
///   - Enter saves the card and clears the field for the next one,
///     keeping the overlay open. Ten ideas in fifteen seconds.
///   - Escape (or tapping the dismiss button) closes the overlay.
///
/// Stateful so it can manage its own controller + focus node and keep
/// itself open across multiple submissions without losing focus.
class QuickCaptureOverlay extends StatefulWidget {
  /// Called for each submission. Receives the trimmed text and the index
  /// of this submission within the current capture session (0-based) so
  /// the parent can fan cards out in a sensible cascade.
  final void Function(String title, int index) onSubmit;
  final VoidCallback onClose;

  const QuickCaptureOverlay({
    super.key,
    required this.onSubmit,
    required this.onClose,
  });

  @override
  State<QuickCaptureOverlay> createState() => _QuickCaptureOverlayState();
}

class _QuickCaptureOverlayState extends State<QuickCaptureOverlay> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  int _captureCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _ctrl.text.trim();
    if (text.isNotEmpty) {
      widget.onSubmit(text, _captureCount);
      _captureCount++;
      _ctrl.clear();
    }
    // Re-focus for the next submission regardless of whether this one
    // was empty — keeps the rhythm of typing → Enter → typing.
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // Push above mid-screen so the overlay never sits on top of the
        // editor side-panel if one happens to open mid-session.
        padding: const EdgeInsets.only(bottom: 120),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(color: KColors.amber, width: 1.2),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt,
                    size: 16, color: KColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSubmit(),
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: _captureCount == 0
                            ? 'Capture an idea — Enter to save, '
                                'Esc to close'
                            : '+ $_captureCount captured · keep going',
                        hintStyle: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 12,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close,
                      size: 16, color: KColors.textDim),
                  tooltip: 'Close (Esc)',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import 'canvas_constants.dart';
import 'canvas_link_badge.dart';
import 'canvas_tags.dart';

/// Side-panel editor for a single CanvasCard. Lets the PM edit title,
/// body, colour, size, and (in phase B) link / promote / delete.
class CanvasCardEditor extends StatefulWidget {
  final CanvasCard card;
  final CanvasCardsDao dao;
  final VoidCallback onClosed;

  /// All tag strings already present in the project (without the `#`
  /// prefix). Used to power `#`-autocomplete in the Notes field so the
  /// user gravitates towards existing labels instead of inventing new
  /// near-duplicates. Empty list is fine — the autocomplete row just
  /// stays hidden.
  final List<String> knownTags;

  /// Called when the user picks "Promote to..." — phase B hands the
  /// concrete promotion logic over to canvas_view which knows about
  /// the promotion service.
  final void Function(CanvasCard card)? onPromote;

  /// Called when the user picks "Link to..." — phase B.
  final void Function(CanvasCard card)? onLink;

  /// Called when the user wants to draw a sequence arrow from this card to
  /// another. The parent puts the canvas into "pick target" mode.
  final void Function(CanvasCard card)? onStartSequence;

  /// Called when the user picks "Revert promotion". The parent runs the
  /// revert through PromotionService (which the editor doesn't depend on
  /// directly) so the UX can surface a snackbar.
  final Future<void> Function(CanvasCard card, bool deletePromotedItem)?
      onRevertPromotion;

  const CanvasCardEditor({
    super.key,
    required this.card,
    required this.dao,
    required this.onClosed,
    this.knownTags = const [],
    this.onPromote,
    this.onLink,
    this.onStartSequence,
    this.onRevertPromotion,
  });

  @override
  State<CanvasCardEditor> createState() => _CanvasCardEditorState();
}

class _CanvasCardEditorState extends State<CanvasCardEditor> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _effortCtrl;
  late String? _colour;
  late String _size;
  late String? _startDate;
  late String? _endDate;
  late int? _effortDays;
  String? _dateError;
  // Live preview — recomputed on every body keystroke so the user sees
  // a chip appear the moment they finish typing a `#tag`.
  List<String> _currentTags = const [];
  // Autocomplete state — non-null when the user is mid-`#tag` and there
  // is at least one matching known tag to suggest.
  TagSuggestion? _suggestion;
  // Focus on the Notes field — hides the autocomplete strip when the
  // user moves keyboard focus elsewhere (so it doesn't linger over the
  // colour swatches).
  final FocusNode _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.card.title);
    _bodyCtrl = TextEditingController(text: widget.card.body ?? '');
    _colour = widget.card.colour;
    _size = widget.card.size;
    _startDate = widget.card.startDate;
    _endDate = widget.card.endDate;
    _effortDays = widget.card.effortDays;
    _effortCtrl =
        TextEditingController(text: _effortDays?.toString() ?? '');
    _currentTags = CanvasTags.extractFromBody(widget.card.body);
    _bodyCtrl.addListener(_recomputeSuggestion);
    _bodyFocus.addListener(_recomputeSuggestion);
  }

  @override
  void didUpdateWidget(covariant CanvasCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _titleCtrl.text = widget.card.title;
      _bodyCtrl.text = widget.card.body ?? '';
      _colour = widget.card.colour;
      _size = widget.card.size;
      _startDate = widget.card.startDate;
      _endDate = widget.card.endDate;
      _effortDays = widget.card.effortDays;
      _effortCtrl.text = _effortDays?.toString() ?? '';
      _dateError = null;
      _currentTags = CanvasTags.extractFromBody(widget.card.body);
    }
  }

  void _onBodyChanged() {
    final next = CanvasTags.extractFromBody(_bodyCtrl.text);
    if (!_tagListEquals(next, _currentTags)) {
      setState(() => _currentTags = next);
    }
    _save();
  }

  bool _tagListEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _bodyCtrl.removeListener(_recomputeSuggestion);
    _bodyFocus.removeListener(_recomputeSuggestion);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _effortCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Re-evaluates whether the caret sits inside an in-progress `#tag`
  /// and, if so, finds matching candidates from [widget.knownTags].
  /// Wired to both controller and focus changes so the strip disappears
  /// the moment the user leaves the Notes field.
  void _recomputeSuggestion() {
    if (!_bodyFocus.hasFocus || widget.knownTags.isEmpty) {
      if (_suggestion != null) setState(() => _suggestion = null);
      return;
    }
    final selection = _bodyCtrl.selection;
    // Only suggest when there's a real, collapsed caret position.
    if (!selection.isValid || !selection.isCollapsed) {
      if (_suggestion != null) setState(() => _suggestion = null);
      return;
    }
    final next = CanvasTags.suggestionAt(
      _bodyCtrl.text,
      selection.baseOffset,
      widget.knownTags,
    );
    final showable = (next != null && next.isNotEmpty) ? next : null;
    if (!_suggestionEquals(showable, _suggestion)) {
      setState(() => _suggestion = showable);
    }
  }

  bool _suggestionEquals(TagSuggestion? a, TagSuggestion? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.start != b.start || a.end != b.end || a.prefix != b.prefix) {
      return false;
    }
    if (a.matches.length != b.matches.length) return false;
    for (var i = 0; i < a.matches.length; i++) {
      if (a.matches[i] != b.matches[i]) return false;
    }
    return true;
  }

  /// Replaces the in-progress `#prefix` with `#tag` and parks the caret
  /// right after it. Also kicks off a save so the resulting tag lands
  /// in the canonical tags column.
  void _acceptSuggestion(String tag) {
    final current = _suggestion;
    if (current == null) return;
    final result = current.accept(_bodyCtrl.text, tag);
    _bodyCtrl.value = TextEditingValue(
      text: result.body,
      selection: TextSelection.collapsed(offset: result.caret),
    );
    setState(() => _suggestion = null);
    _onBodyChanged();
  }

  /// Validates and persists the date pair. Returns true when the values
  /// are consistent (end ≥ start) and the patch was written.
  bool _validateDates() {
    if (_startDate != null && _endDate != null) {
      if (_endDate!.compareTo(_startDate!) < 0) {
        setState(() => _dateError = 'End date is before the start date.');
        return false;
      }
    }
    setState(() => _dateError = null);
    return true;
  }

  Future<void> _save() async {
    if (!_validateDates()) return;
    final body = _bodyCtrl.text.trim().isEmpty
        ? null
        : _bodyCtrl.text.trim();
    // Parse #tags out of the body on every save so the tags column
    // stays in sync with the source-of-truth body text.
    final tags = CanvasTags.extractFromBody(body);
    await widget.dao.patchCard(
      widget.card.id,
      CanvasCardsCompanion(
        title: Value(_titleCtrl.text.trim()),
        body: Value(body),
        colour: Value(_colour),
        size: Value(_size),
        startDate: Value(_startDate),
        endDate: Value(_endDate),
        effortDays: Value(_effortDays),
        tags: Value(CanvasTags.encode(tags)),
      ),
    );
  }

  /// Parses the effort input. Treats empty/whitespace and invalid input
  /// as "no estimate". Negative or zero values are rejected (treated as
  /// no estimate) so a drag-drop never produces a backwards range.
  void _onEffortChanged(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() => _effortDays = null);
    } else {
      final v = int.tryParse(trimmed);
      setState(() => _effortDays = (v == null || v <= 0) ? null : v);
    }
    _save();
  }

  Future<void> _delete() async {
    await widget.dao.deleteCard(widget.card.id);
    if (mounted) widget.onClosed();
  }

  /// Confirms what to do with the formal item that promotion created
  /// before reverting. Three outcomes:
  ///   - Cancel (default): nothing changes.
  ///   - "Just unlink": clear the card's promotion fields, leave the
  ///     Action/Risk/etc in place.
  ///   - "Unlink and delete the [type]": clear promotion + delete the
  ///     formal item from its source module.
  Future<void> _confirmRevert() async {
    final on = widget.onRevertPromotion;
    if (on == null) return;
    final typeLabel = CanvasLinkBadge.labelForType(
        widget.card.promotedToType ?? 'item');
    final choice = await showDialog<_RevertChoice>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: KColors.border),
        ),
        title: const Text(
          'Revert promotion?',
          style: TextStyle(
            color: KColors.amber,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This card was promoted to a $typeLabel. What should happen '
          'to the $typeLabel itself?',
          style: const TextStyle(
            color: KColors.textDim,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_RevertChoice.unlinkOnly),
            child: const Text('Just unlink'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: KColors.redDim,
              foregroundColor: KColors.red,
              elevation: 0,
            ),
            onPressed: () =>
                Navigator.of(context).pop(_RevertChoice.unlinkAndDelete),
            child: Text('Unlink and delete the $typeLabel'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await on(widget.card, choice == _RevertChoice.unlinkAndDelete);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(
          left: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(card: widget.card, onClose: widget.onClosed),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionLabel('Title'),
                  TextField(
                    controller: _titleCtrl,
                    maxLines: 2,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _fieldDecoration('A short title'),
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 14),
                  const _SectionLabel('Notes'),
                  TextField(
                    controller: _bodyCtrl,
                    focusNode: _bodyFocus,
                    maxLines: 8,
                    minLines: 4,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                    decoration: _fieldDecoration(
                        'Free-form thinking… type #tag to tag'),
                    onChanged: (_) => _onBodyChanged(),
                  ),
                  // Autocomplete strip — visible only while the caret
                  // sits inside an in-progress `#tag` with at least one
                  // matching known tag.
                  if (_suggestion != null) ...[
                    const SizedBox(height: 6),
                    _TagSuggestionStrip(
                      suggestion: _suggestion!,
                      onPick: _acceptSuggestion,
                    ),
                  ],
                  // Live tag preview — chips appear as the user finishes
                  // typing each `#tag`. Hidden when there are no tags.
                  if (_currentTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _EditorTagChips(tags: _currentTags),
                  ],
                  const SizedBox(height: 18),
                  const _SectionLabel('Colour'),
                  _ColourPicker(
                    selected: _colour,
                    onChanged: (v) {
                      setState(() => _colour = v);
                      _save();
                    },
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('Size'),
                  _SizePicker(
                    selected: _size,
                    onChanged: (v) {
                      setState(() => _size = v);
                      _save();
                    },
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('Dates'),
                  Row(
                    children: [
                      Expanded(
                        child: DatePickerField(
                          key: ValueKey('start-${widget.card.id}'),
                          label: 'Start',
                          isoValue: _startDate,
                          onChanged: (v) {
                            setState(() => _startDate = v);
                            _save();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DatePickerField(
                          key: ValueKey('end-${widget.card.id}'),
                          label: 'End',
                          isoValue: _endDate,
                          onChanged: (v) {
                            setState(() => _endDate = v);
                            _save();
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_dateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _dateError!,
                        style: const TextStyle(
                          color: KColors.red,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else if (_startDate == null &&
                      _endDate == null &&
                      widget.card.linkedItemType != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No dates set — calendar uses the linked item\'s date.',
                        style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  const _SectionLabel('Effort (days)'),
                  TextField(
                    controller: _effortCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                    ),
                    decoration: _fieldDecoration('e.g. 7 = 1 week'),
                    onChanged: _onEffortChanged,
                  ),
                  if (_startDate == null && _endDate == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _effortDays != null
                            ? 'Dragging from the No-date sidebar will '
                                'place this as a $_effortDays-day bar.'
                            : 'No effort set — sidebar drops default to '
                                '7 days.',
                        style: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (widget.card.linkedItemType != null) ...[
                    const _SectionLabel('Linked item'),
                    Row(
                      children: [
                        CanvasLinkBadge(
                          itemType: widget.card.linkedItemType!,
                          itemId: widget.card.linkedItemId,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => widget.dao.patchCard(
                            widget.card.id,
                            const CanvasCardsCompanion(
                              linkedItemType: Value(null),
                              linkedItemId: Value(null),
                            ),
                          ),
                          child: const Text('Unlink'),
                        ),
                      ],
                    ),
                  ] else if (widget.onLink != null) ...[
                    TextButton.icon(
                      onPressed: () => widget.onLink!(widget.card),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Link to…'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (widget.onStartSequence != null) ...[
                    TextButton.icon(
                      onPressed: () =>
                          widget.onStartSequence!(widget.card),
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('Add arrow to…'),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (widget.card.promotedAt == null &&
                      widget.onPromote != null)
                    OutlinedButton.icon(
                      onPressed: () => widget.onPromote!(widget.card),
                      icon: const Icon(Icons.north_east, size: 16),
                      label: const Text('Promote to…'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KColors.amber,
                        side: const BorderSide(color: KColors.amber),
                      ),
                    ),
                  if (widget.card.promotedAt != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      decoration: BoxDecoration(
                        color: KColors.phosDim.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: KColors.phosphor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: KColors.phosphor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Promoted to '
                              '${CanvasLinkBadge.labelForType(widget.card.promotedToType ?? 'item')}',
                              style: const TextStyle(
                                color: KColors.phosphor,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          if (widget.onRevertPromotion != null)
                            TextButton(
                              onPressed: _confirmRevert,
                              style: TextButton.styleFrom(
                                foregroundColor: KColors.phosphor,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                minimumSize: const Size(0, 24),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                textStyle:
                                    const TextStyle(fontSize: 11),
                              ),
                              child: const Text('Revert'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: KColors.red),
                    label: const Text('Delete card',
                        style: TextStyle(color: KColors.red)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: KColors.textMuted, fontSize: 12),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: KColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: KColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: KColors.amber),
      ),
    );
  }
}

enum _RevertChoice { unlinkOnly, unlinkAndDelete }

/// Compact horizontal strip of `#tag` suggestion buttons. Sits directly
/// under the Notes field while the caret is in an active `#tag`
/// context; tapping a chip replaces the typed prefix with the chosen
/// known tag.
class _TagSuggestionStrip extends StatelessWidget {
  final TagSuggestion suggestion;
  final ValueChanged<String> onPick;

  const _TagSuggestionStrip({
    required this.suggestion,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in suggestion.matches)
          InkWell(
            key: ValueKey('tag-suggestion-$tag'),
            onTap: () => onPick(tag),
            borderRadius: BorderRadius.circular(3),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.surface2,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: KColors.amber.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Text(
                '#$tag',
                style: const TextStyle(
                  color: KColors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Live-preview chips for the editor side panel. Same visual language as
/// the on-card tag pills so users see consistent feedback.
class _EditorTagChips extends StatelessWidget {
  final List<String> tags;

  const _EditorTagChips({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 4,
      children: tags
          .map((t) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: KColors.amberDim.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: KColors.amber.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '#$t',
                  style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _Header extends StatelessWidget {
  final CanvasCard card;
  final VoidCallback onClose;

  const _Header({required this.card, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CanvasLayout.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined,
              size: 16, color: KColors.textDim),
          const SizedBox(width: 8),
          const Text(
            'EDIT CARD',
            style: TextStyle(
              color: KColors.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18, color: KColors.textDim),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: KColors.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _ColourPicker extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _ColourPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        _swatch(null, KColors.border, 'None'),
        ...CanvasCardColours.all.map((key) => _swatch(
              key,
              CanvasCardColours.palette[key]!,
              key,
            )),
      ],
    );
  }

  Widget _swatch(String? value, Color colour, String tooltip) {
    final isSelected = value == selected;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: value == null ? KColors.surface2 : colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? KColors.amber : KColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: value == null
              ? const Center(
                  child: Icon(Icons.block, size: 12, color: KColors.textDim),
                )
              : null,
        ),
      ),
    );
  }
}

class _SizePicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _SizePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      ('small', 'S'),
      ('medium', 'M'),
      ('large', 'L'),
    ];
    return Row(
      children: options.map((opt) {
        final isSelected = selected == opt.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: OutlinedButton(
            onPressed: () => onChanged(opt.$1),
            style: OutlinedButton.styleFrom(
              foregroundColor: isSelected ? KColors.amber : KColors.textDim,
              side: BorderSide(
                color: isSelected ? KColors.amber : KColors.border,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              minimumSize: const Size(40, 28),
            ),
            child: Text(opt.$2,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        );
      }).toList(),
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../core/analytics/keel_events.dart';
import 'canvas_band.dart';
import 'canvas_card.dart';
import 'canvas_card_editor.dart';
import 'canvas_constants.dart';
import 'canvas_drag_payload.dart';
import 'canvas_filter.dart';
import 'canvas_tags.dart';
import 'quick_capture.dart';
import 'quick_capture_overlay.dart';
import 'templates/template_shell.dart';
import 'templates/templates_gallery_view.dart';
import 'promotion/promote_to_dialog.dart';
import 'promotion/promotion_service.dart';
import 'views/canvas_calendar_view.dart';
import 'views/canvas_list_view.dart';

enum CanvasViewMode { grid, list, calendar }

/// Section-level tab in the Canvas header. Three Bands is the existing
/// free-form thinking surface; Templates is the gallery + per-instance
/// page added in Phase 2 of Canvas v2.
enum CanvasSection { threeBands, templates }

/// Canvas — the PM's strategic thinking surface. Three vertical bands
/// (This Week, Next 30 Days, Horizon) with free-positioned cards.
///
/// When [initialQuickCapture] is true, the quick-capture overlay opens
/// on first build. Used by the SPC t n leader chord which navigates to
/// Canvas and drops the user straight into capture mode.
class CanvasView extends StatefulWidget {
  final bool initialQuickCapture;

  const CanvasView({super.key, this.initialQuickCapture = false});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  String? _editingCardId;
  String? _draggingCardId;
  /// When non-null, the next card tap creates a sequence arrow from this id
  /// to the tapped card. Set by the "Add arrow to…" button in the editor.
  String? _sequenceSourceCardId;
  CanvasViewMode _viewMode = CanvasViewMode.grid;
  CanvasFilter _filter = CanvasFilter.empty;
  /// Per-session toggle: when true, the grid view swaps the three-band
  /// layout for clusters grouped by tag. Resets on app restart so the
  /// default canvas remains the free-positioned bands view.
  bool _groupByTag = false;

  /// Section-level navigation within Canvas. Three Bands is the default;
  /// Templates flips the body to a gallery + per-instance shell.
  CanvasSection _section = CanvasSection.threeBands;

  /// When [_section] is Templates and this is non-null, the gallery is
  /// replaced by the template's own page. Back-from-template clears it.
  String? _openTemplateId;

  /// Quick-capture mode — when true, the QuickCaptureOverlay is rendered
  /// over the canvas and the user can drop ideas in fast succession.
  /// Triggered by the `N` key (when no text field has focus) or by
  /// arriving on Canvas via the SPC t n leader chord.
  bool _captureMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuickCapture) {
      // Schedule for after first frame so the overlay's autofocus runs
      // after the focus tree is settled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _captureMode = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const _NoProjectState();
    }
    final db = context.read<AppDatabase>();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event, projectId, db),
      child: StreamBuilder<List<CanvasCard>>(
        stream: db.canvasCardsDao.watchCardsForProject(projectId),
        builder: (context, snapshot) {
          final allCards = snapshot.data ?? const <CanvasCard>[];
          final cards = _filter.apply(allCards);
          return StreamBuilder<List<CanvasSequence>>(
            stream: db.canvasCardsDao
                .watchSequencesForProject(projectId),
            builder: (context, seqSnap) {
              final sequences =
                  seqSnap.data ?? const <CanvasSequence>[];
              return _buildScaffold(
                projectId, allCards, cards, sequences);
            },
          );
        },
      ),
    );
  }

  Widget _buildScaffold(
      String projectId,
      List<CanvasCard> allCards,
      List<CanvasCard> cards,
      List<CanvasSequence> sequences) {
    // Build the alphabetised tag → count map from the unfiltered card
    // list so the filter UI sees every tag in the project, not just the
    // ones surviving the current filter.
    final tagCounts = <String, int>{};
    for (final c in allCards) {
      for (final t in CanvasTags.decode(c.tags)) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final sortedTags = tagCounts.keys.toList()..sort();
    final orderedTagCounts = {
      for (final k in sortedTags) k: tagCounts[k]!,
    };
          final isThreeBands = _section == CanvasSection.threeBands;
          return Column(
            children: [
              _Header(
                projectName:
                    context.read<ProjectProvider>().currentProject?.name ??
                        '',
                section: _section,
                onSectionChanged: (s) => setState(() {
                  _section = s;
                  // Reset open template when switching sections.
                  if (s == CanvasSection.threeBands) {
                    _openTemplateId = null;
                  }
                }),
                viewMode: _viewMode,
                cardCount: cards.length,
                onViewModeChanged: (m) => setState(() => _viewMode = m),
                groupByTag: _groupByTag,
                onGroupByTagChanged: (v) =>
                    setState(() => _groupByTag = v),
                filter: _filter,
                onFilterChanged: (f) => setState(() => _filter = f),
                tagCounts: orderedTagCounts,
                onNewCard: () => _createCard(
                  projectId: projectId,
                  band: CanvasBands.thisWeek,
                  localOffset: CanvasLayout.defaultDropOffset,
                ),
              ),
              if (isThreeBands && _sequenceSourceCardId != null)
                _SequencingBanner(
                  onCancel: () =>
                      setState(() => _sequenceSourceCardId = null),
                ),
              Expanded(
                child: isThreeBands
                    ? _buildThreeBandsArea(
                        projectId, cards, sequences, sortedTags)
                    : _buildTemplatesArea(projectId),
              ),
            ],
          );
  }

  Widget _buildThreeBandsArea(
      String projectId,
      List<CanvasCard> cards,
      List<CanvasSequence> sequences,
      List<String> knownTags) {
    return Stack(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildBody(projectId, cards, sequences),
                        ),
                        if (_editingCardId != null)
                          _buildEditor(
                            projectId,
                            cards,
                            knownTags,
                          ),
                      ],
                    ),
                    if (_captureMode)
                      Positioned.fill(
                        child: QuickCaptureOverlay(
                          onSubmit: (title, index) =>
                              _onQuickCaptureSubmit(
                                  projectId, title, index),
                          onClose: _closeQuickCapture,
                        ),
                      ),
                  ],
                );
  }

  Widget _buildTemplatesArea(String projectId) {
    final id = _openTemplateId;
    if (id == null) {
      return TemplatesGalleryView(
        projectId: projectId,
        onOpen: (templateId) =>
            setState(() => _openTemplateId = templateId),
      );
    }
    return TemplateShell(
      templateId: id,
      onBack: () => setState(() => _openTemplateId = null),
    );
  }

  Widget _buildBody(String projectId, List<CanvasCard> cards,
      List<CanvasSequence> sequences) {
    switch (_viewMode) {
      case CanvasViewMode.grid:
        return _buildGrid(projectId, cards, sequences);
      case CanvasViewMode.list:
        return CanvasListView(
          cards: cards,
          onTap: _onTapCard,
        );
      case CanvasViewMode.calendar:
        return CanvasCalendarView(
          projectId: projectId,
          cards: cards,
          onTap: _onTapCard,
        );
    }
  }

  Widget _buildGrid(String projectId, List<CanvasCard> cards,
      List<CanvasSequence> sequences) {
    if (_groupByTag) return _buildGroupByTag(cards);
    final byBand = <String, List<CanvasCard>>{
      for (final b in CanvasBands.all) b: [],
    };
    for (final c in cards) {
      (byBand[c.band] ??= []).add(c);
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final band in CanvasBands.all)
            CanvasBand(
              band: band,
              title: CanvasBands.label(band),
              cards: byBand[band] ?? const [],
              sequences: sequences,
              isFocusBand: band == CanvasBands.thisWeek,
              sequenceSourceCardId: _sequenceSourceCardId,
              onTapEmpty: (offset) => _createCard(
                projectId: projectId,
                band: band,
                localOffset: offset,
              ),
              onAcceptCard: (drag, offset) =>
                  _moveCard(drag, band, offset),
              onAcceptExternal: (drag, offset) => _createLinkedCard(
                projectId: projectId,
                band: band,
                localOffset: offset,
                drag: drag,
              ),
              onTapCard: _onTapCard,
              onEditCard: _onTapCard,
              onLongPressCard: (card) => _showContextMenu(context, card),
              draggingCardId: _draggingCardId,
              onDraggingCardChanged: (id) =>
                  setState(() => _draggingCardId = id),
            ),
        ],
      ),
    );
  }

  /// Tag-clustered alternative to the three-band grid. Each known tag
  /// becomes a haloed section whose body is a Wrap of the cards carrying
  /// that tag; cards with multiple tags appear in every cluster they
  /// belong to (so an integration card tagged "risk" shows up in both
  /// the #integration and #risk clusters — that's the pattern-recognition
  /// affordance). Cards with no tags are collected into a final "No tag"
  /// cluster.
  Widget _buildGroupByTag(List<CanvasCard> cards) {
    final byTag = <String, List<CanvasCard>>{};
    final untagged = <CanvasCard>[];
    for (final c in cards) {
      final tags = CanvasTags.decode(c.tags);
      if (tags.isEmpty) {
        untagged.add(c);
        continue;
      }
      for (final t in tags) {
        (byTag[t] ??= []).add(c);
      }
    }
    final orderedTags = byTag.keys.toList()..sort();
    final hasAnything = orderedTags.isNotEmpty || untagged.isNotEmpty;
    if (!hasAnything) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No cards yet — switch to Free position to add some.',
            style: TextStyle(color: KColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tag in orderedTags)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _TagCluster(
                tag: tag,
                cards: byTag[tag]!,
                onTapCard: _onTapCard,
              ),
            ),
          if (untagged.isNotEmpty)
            _TagCluster(
              tag: null,
              cards: untagged,
              onTapCard: _onTapCard,
            ),
        ],
      ),
    );
  }

  Widget _buildEditor(
      String projectId, List<CanvasCard> cards, List<String> knownTags) {
    final card =
        cards.where((c) => c.id == _editingCardId).cast<CanvasCard?>().firstOrNull;
    if (card == null) {
      // Card may have been deleted — close panel.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _editingCardId = null);
      });
      return const SizedBox.shrink();
    }
    final db = context.read<AppDatabase>();
    return CanvasCardEditor(
      key: ValueKey(card.id),
      card: card,
      dao: db.canvasCardsDao,
      knownTags: knownTags,
      onClosed: () => setState(() => _editingCardId = null),
      onPromote: (c) => _promoteCard(c, projectId),
      onLink: null, // link picker is left as a follow-up; drag-in covers it
      onStartSequence: (c) {
        setState(() {
          _sequenceSourceCardId = c.id;
          _editingCardId = null;
        });
      },
      onRevertPromotion: _revertPromotion,
    );
  }

  Future<void> _revertPromotion(
      CanvasCard card, bool deletePromotedItem) async {
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    final service = PromotionService(db);
    final promotedTypeLabel = card.promotedToType ?? 'item';
    final ok = await service.revert(
      card,
      deletePromotedItem: deletePromotedItem,
    );
    if (!ok || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deletePromotedItem
              ? 'Reverted promotion and deleted the $promotedTypeLabel.'
              : 'Reverted promotion. The $promotedTypeLabel is unchanged.',
        ),
      ),
    );
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _createCard({
    required String projectId,
    required String band,
    required Offset localOffset,
    String title = '',
    String? body,
    ExternalItemDragData? external,
  }) async {
    final db = context.read<AppDatabase>();
    final id = const Uuid().v4();
    final effectiveBody = external?.body ?? body;
    // Parse tags from both title (quick-capture writes ideas there) and
    // body (editor / paste / drag-in) so #tags work wherever the user
    // types them in this fast-creation flow.
    final tagSources = [
      external?.title ?? title,
      effectiveBody,
    ].whereType<String>().join('\n');
    final tags = CanvasTags.extractFromBody(tagSources);
    await db.canvasCardsDao.insertCard(
      CanvasCardsCompanion.insert(
        id: id,
        projectId: projectId,
        title: external?.title ?? title,
        body: Value(effectiveBody),
        band: Value(band),
        positionX: Value(localOffset.dx.round().clamp(0, 99999)),
        positionY: Value(localOffset.dy.round().clamp(0, 99999)),
        linkedItemType: Value(external?.itemType),
        linkedItemId: Value(external?.itemId),
        tags: Value(CanvasTags.encode(tags)),
      ),
    );
    if (mounted) {
      context.analytics.track(
        KeelEvents.cardCreated,
        props: {
          KeelEventProps.source: external != null
              ? 'drag_in'
              : (title.isEmpty ? 'new_button' : 'quick_capture'),
        },
      );
    }
    if (title.isEmpty && external == null) {
      setState(() => _editingCardId = id);
    }
  }

  Future<void> _createLinkedCard({
    required String projectId,
    required String band,
    required Offset localOffset,
    required ExternalItemDragData drag,
  }) async {
    final db = context.read<AppDatabase>();
    final existing = await db.canvasCardsDao.findCardLinkedTo(
      projectId: projectId,
      itemType: drag.itemType,
      itemId: drag.itemId,
    );
    if (existing != null) {
      // Already on canvas — move to drop band + position instead of dupe.
      await db.canvasCardsDao.patchCard(
        existing.id,
        CanvasCardsCompanion(
          band: Value(band),
          positionX: Value(localOffset.dx.round()),
          positionY: Value(localOffset.dy.round()),
        ),
      );
      return;
    }
    await _createCard(
      projectId: projectId,
      band: band,
      localOffset: localOffset,
      external: drag,
    );
  }

  Future<void> _moveCard(
    CanvasCardDragData drag,
    String targetBand,
    Offset localOffset,
  ) async {
    final db = context.read<AppDatabase>();
    final adjusted = Offset(
      (localOffset.dx - drag.pointerOffsetInCard.dx)
          .clamp(0, double.infinity),
      (localOffset.dy - drag.pointerOffsetInCard.dy)
          .clamp(0, double.infinity),
    );
    await db.canvasCardsDao.patchCard(
      drag.card.id,
      CanvasCardsCompanion(
        band: Value(targetBand),
        positionX: Value(adjusted.dx.round()),
        positionY: Value(adjusted.dy.round()),
      ),
    );
  }

  void _onTapCard(CanvasCard card) {
    // If we're in "pick sequence target" mode, complete the sequence.
    final source = _sequenceSourceCardId;
    if (source != null && source != card.id) {
      _createSequence(source, card.id, card.projectId);
      return;
    }
    setState(() => _editingCardId = card.id);
  }

  Future<void> _createSequence(
      String fromId, String toId, String projectId) async {
    final db = context.read<AppDatabase>();
    await db.canvasCardsDao.addSequence(
      id: const Uuid().v4(),
      projectId: projectId,
      fromCardId: fromId,
      toCardId: toId,
    );
    if (mounted) setState(() => _sequenceSourceCardId = null);
  }

  Future<void> _showContextMenu(
      BuildContext context, CanvasCard card) async {
    final db = context.read<AppDatabase>();
    final projectId =
        context.read<ProjectProvider>().currentProjectId;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(200, 200, 200, 200),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'promote', child: Text('Promote to…')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (selected == null) return;
    switch (selected) {
      case 'edit':
        if (mounted) setState(() => _editingCardId = card.id);
        break;
      case 'promote':
        if (projectId != null) _promoteCard(card, projectId);
        break;
      case 'duplicate':
        await db.canvasCardsDao.insertCard(
          CanvasCardsCompanion.insert(
            id: const Uuid().v4(),
            projectId: card.projectId,
            title: '${card.title} (copy)',
            body: Value(card.body),
            band: Value(card.band),
            positionX: Value(card.positionX + 24),
            positionY: Value(card.positionY + 24),
            colour: Value(card.colour),
            size: Value(card.size),
          ),
        );
        break;
      case 'delete':
        await db.canvasCardsDao.deleteCard(card.id);
        break;
    }
  }

  Future<void> _promoteCard(CanvasCard card, String projectId) async {
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    final target = await showDialog<String>(
      context: context,
      builder: (_) => const PromoteToDialog(),
    );
    if (target == null) return;
    final service = PromotionService(db);
    await service.promote(card: card, targetType: target);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Promoted to $target.')),
    );
  }

  // ---- Keyboard -----------------------------------------------------------

  KeyEventResult _handleKeyEvent(
      KeyEvent event, String projectId, AppDatabase db) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // When focus is on a TextField anywhere in the canvas (title, body,
    // search, etc.), key events bubble up to this handler. We must NOT
    // claim them as shortcuts or the user can't type 'n' or paste into
    // the field normally.
    if (_isTextInputFocused()) return KeyEventResult.ignored;

    // Quick-capture: `N` (no modifiers) opens the overlay. Active only
    // in the three-band view. The overlay's own TextField captures
    // Enter for submission and Escape to close, so its key events
    // never re-trigger this handler.
    final isPlainN = event.logicalKey == LogicalKeyboardKey.keyN &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isShiftPressed;
    if (isPlainN &&
        !_captureMode &&
        _viewMode == CanvasViewMode.grid &&
        _section == CanvasSection.threeBands) {
      setState(() => _captureMode = true);
      return KeyEventResult.handled;
    }

    // Cmd/Ctrl+V — paste-to-create. Multi-line clipboards produce one
    // card per non-blank line (the brainstorm dump case); single-line
    // produces a single card.
    final isPaste = event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed);
    if (isPaste) {
      Clipboard.getData('text/plain').then((data) {
        final lines = QuickCaptureLayout.splitLines(data?.text);
        if (lines.isEmpty) return;
        for (var i = 0; i < lines.length; i++) {
          _createCard(
            projectId: projectId,
            band: CanvasBands.thisWeek,
            localOffset: QuickCaptureLayout.positionFor(i),
            title: lines[i],
          );
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// True when the user is typing in any TextField under the canvas
  /// (title, notes, search, effort input, template title, etc.). Used
  /// to suppress keyboard shortcuts so they don't swallow normal typing.
  bool _isTextInputFocused() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return false;
    final ctx = node.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    // Some focus nodes sit above EditableText (e.g. the Focus widget
    // TextField installs around its EditableText) — check ancestors too.
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ---- Quick-capture overlay ---------------------------------------------

  Future<void> _onQuickCaptureSubmit(
      String projectId, String title, int index) async {
    await _createCard(
      projectId: projectId,
      band: CanvasBands.thisWeek,
      localOffset: QuickCaptureLayout.positionFor(index),
      title: title,
    );
  }

  void _closeQuickCapture() {
    setState(() => _captureMode = false);
  }
}

class _Header extends StatelessWidget {
  final String projectName;
  final CanvasSection section;
  final ValueChanged<CanvasSection> onSectionChanged;
  final CanvasViewMode viewMode;
  final int cardCount;
  final ValueChanged<CanvasViewMode> onViewModeChanged;
  final CanvasFilter filter;
  final ValueChanged<CanvasFilter> onFilterChanged;
  final Map<String, int> tagCounts;
  final VoidCallback onNewCard;
  final bool groupByTag;
  final ValueChanged<bool> onGroupByTagChanged;

  const _Header({
    required this.projectName,
    required this.section,
    required this.onSectionChanged,
    required this.viewMode,
    required this.cardCount,
    required this.onViewModeChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.tagCounts,
    required this.onNewCard,
    required this.groupByTag,
    required this.onGroupByTagChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CanvasLayout.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'CANVAS',
            style: TextStyle(
              color: KColors.amber,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          if (projectName.isNotEmpty) ...[
            const SizedBox(width: 8),
            // Flexible + ellipsis so a long project name shrinks
            // instead of pushing the toolbar past the right edge on
            // narrower viewports.
            Flexible(
              child: Text(
                '· $projectName',
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
          const SizedBox(width: 14),
          _SectionTabs(
            section: section,
            onChanged: onSectionChanged,
          ),
          // Controls: right-aligned; scroll horizontally when the
          // viewport is squeezed (journal dock / Claude panel) rather
          // than overflowing the header.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (section == CanvasSection.threeBands) ...[
                      const SizedBox(width: 12),
                      Text(
                        '$cardCount cards',
                        style: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          onChanged: (v) =>
                              onFilterChanged(filter.copyWith(search: v)),
                          decoration: InputDecoration(
                            hintText: 'Search canvas…',
                            hintStyle: const TextStyle(
                                color: KColors.textMuted, fontSize: 12),
                            isDense: true,
                            prefixIcon: const Icon(Icons.search,
                                size: 14, color: KColors.textDim),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide:
                                  const BorderSide(color: KColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide:
                                  const BorderSide(color: KColors.border),
                            ),
                          ),
                          style: const TextStyle(
                              color: KColors.text, fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _FilterButton(
                        filter: filter,
                        tagCounts: tagCounts,
                        onChanged: onFilterChanged,
                      ),
                      const SizedBox(width: 16),
                      if (viewMode == CanvasViewMode.grid) ...[
                        _GroupByTagToggle(
                          value: groupByTag,
                          onChanged: onGroupByTagChanged,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _ViewModeToggle(
                          value: viewMode, onChanged: onViewModeChanged),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: onNewCard,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('New card'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KColors.amberDim,
                          foregroundColor: KColors.amber,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: const BorderSide(
                                color: KColors.amber, width: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section-level tab toggle in the canvas header: [Three Bands][Templates].
class _SectionTabs extends StatelessWidget {
  final CanvasSection section;
  final ValueChanged<CanvasSection> onChanged;

  const _SectionTabs({required this.section, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(CanvasSection s, String label, IconData icon) {
      final isOn = section == s;
      return InkWell(
        onTap: () => onChanged(s),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isOn ? KColors.amberDim : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13,
                  color: isOn ? KColors.amber : KColors.textDim),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isOn ? KColors.amber : KColors.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          tab(CanvasSection.threeBands, 'Three Bands',
              Icons.view_agenda_outlined),
          tab(CanvasSection.templates, 'Templates',
              Icons.dashboard_customize_outlined),
        ],
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final CanvasViewMode value;
  final ValueChanged<CanvasViewMode> onChanged;

  const _ViewModeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget mk(CanvasViewMode m, IconData icon, String tooltip) {
      final isOn = value == m;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => onChanged(m),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOn ? KColors.amberDim : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon,
                size: 16, color: isOn ? KColors.amber : KColors.textDim),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          mk(CanvasViewMode.grid, Icons.grid_view, 'Three bands'),
          mk(CanvasViewMode.list, Icons.view_list, 'List'),
          mk(CanvasViewMode.calendar, Icons.calendar_month, 'Calendar'),
        ],
      ),
    );
  }
}

/// Pill-style toggle that swaps the three-band grid for a tag-clustered
/// layout. Sits beside the view-mode toggle and is only rendered when
/// the grid view is selected (the other view modes already collapse the
/// bands).
class _GroupByTagToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GroupByTagToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isOn = value;
    return Tooltip(
      message: isOn ? 'Switch to free position' : 'Group by tag',
      child: InkWell(
        onTap: () => onChanged(!isOn),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isOn ? KColors.amberDim : Colors.transparent,
            border: Border.all(
              color: isOn ? KColors.amber : KColors.border,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bubble_chart_outlined,
                  size: 14,
                  color: isOn ? KColors.amber : KColors.textDim),
              const SizedBox(width: 6),
              Text(
                'Group by tag',
                style: TextStyle(
                  color: isOn ? KColors.amber : KColors.textDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single tag's cluster card: a soft amber halo containing the tag
/// label + count plus a Wrap of the cards carrying that tag. Untagged
/// cards are passed with [tag] == null, which renders as "No tag".
class _TagCluster extends StatelessWidget {
  final String? tag;
  final List<CanvasCard> cards;
  final ValueChanged<CanvasCard> onTapCard;

  const _TagCluster({
    required this.tag,
    required this.cards,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    final label = tag == null ? 'No tag' : '#$tag';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: tag == null
            ? KColors.surface
            : KColors.amberDim.withValues(alpha: 0.18),
        border: Border.all(
          color: tag == null
              ? KColors.border
              : KColors.amber.withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tag == null ? KColors.textDim : KColors.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${cards.length}',
                style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in cards)
                CanvasCardWidget(
                  key: ValueKey('group-${tag ?? "none"}-${c.id}'),
                  card: c,
                  onTap: () => onTapCard(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final CanvasFilter filter;
  final Map<String, int> tagCounts;
  final ValueChanged<CanvasFilter> onChanged;

  const _FilterButton({
    required this.filter,
    required this.tagCounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = filter.activeCount;
    return PopupMenuButton<String>(
      tooltip: 'Filters',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.filter_alt_outlined,
              size: 18, color: KColors.textDim),
          if (active > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: KColors.amber,
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  '$active',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: KColors.bg,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      itemBuilder: (_) => [
        _section('Band'),
        _check('All', filter.band == null,
            () => onChanged(filter.copyWith(band: null))),
        _check('This Week', filter.band == CanvasBands.thisWeek,
            () => onChanged(filter.copyWith(band: CanvasBands.thisWeek))),
        _check('Next 30 Days', filter.band == CanvasBands.next30Days,
            () => onChanged(filter.copyWith(band: CanvasBands.next30Days))),
        _check('Horizon', filter.band == CanvasBands.horizon,
            () => onChanged(filter.copyWith(band: CanvasBands.horizon))),
        _section('Link'),
        _check('All', filter.linked == null,
            () => onChanged(filter.copyWith(linked: null))),
        _check('Linked only', filter.linked == 'linked',
            () => onChanged(filter.copyWith(linked: 'linked'))),
        _check('Free-form only', filter.linked == 'free',
            () => onChanged(filter.copyWith(linked: 'free'))),
        _section('Promotion'),
        _check('All', filter.promoted == null,
            () => onChanged(filter.copyWith(promoted: null))),
        _check('Promoted', filter.promoted == 'promoted',
            () => onChanged(filter.copyWith(promoted: 'promoted'))),
        _check('Not promoted', filter.promoted == 'not_promoted',
            () => onChanged(filter.copyWith(promoted: 'not_promoted'))),
        if (tagCounts.isNotEmpty) ...[
          _section('Tag'),
          _check('All', filter.tag == null,
              () => onChanged(filter.copyWith(tag: null))),
          for (final entry in tagCounts.entries)
            _check(
              '#${entry.key}  ·  ${entry.value}',
              filter.tag == entry.key,
              () => onChanged(filter.copyWith(tag: entry.key)),
            ),
        ],
      ],
    );
  }

  PopupMenuItem<String> _section(String label) {
    return PopupMenuItem(
      enabled: false,
      child: Text(label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: KColors.textMuted,
            letterSpacing: 1.4,
          )),
    );
  }

  PopupMenuItem<String> _check(String label, bool selected, VoidCallback on) {
    return PopupMenuItem(
      onTap: on,
      child: Row(
        children: [
          Icon(selected ? Icons.check : Icons.check_box_outline_blank,
              size: 14,
              color: selected ? KColors.amber : KColors.textMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SequencingBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _SequencingBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.amberDim,
        border: const Border(
          bottom: BorderSide(color: KColors.amber, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward,
              size: 14, color: KColors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Click another card to draw a sequence arrow to it.',
              style: TextStyle(
                color: KColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _NoProjectState extends StatelessWidget {
  const _NoProjectState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Select a project to open Canvas.',
        style: TextStyle(color: KColors.textDim),
      ),
    );
  }
}

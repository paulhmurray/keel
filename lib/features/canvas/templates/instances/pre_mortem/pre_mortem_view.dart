import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import '../../../../../shared/widgets/person_picker_field.dart';
import 'pre_mortem_model.dart';

/// View for a single Pre-mortem template instance.
///
/// Three sections, top to bottom:
///   1. The Goal — the imagined failure state.
///   2. How did we get here? — list of cause cards.
///   3. Mitigations — nested under each cause.
///
/// Every edit (text typing, level pick, add/remove) immediately writes
/// the serialised JSON back to `CanvasTemplates.content` via the DAO.
/// We hold the parsed [PreMortemContent] in local state so re-renders
/// don't re-parse on every keystroke; on first build (and on id-change)
/// we hydrate from the template prop.
class PreMortemView extends StatefulWidget {
  final CanvasTemplate template;

  const PreMortemView({super.key, required this.template});

  @override
  State<PreMortemView> createState() => _PreMortemViewState();
}

class _PreMortemViewState extends State<PreMortemView> {
  late PreMortemContent _content;
  late final TextEditingController _goalCtrl;
  // One controller per editable text per (cause, mitigation) — keyed
  // by id so we can preserve cursor position across rebuilds.
  final Map<String, TextEditingController> _causeDescCtrls = {};
  final Map<String, TextEditingController> _mitigationDescCtrls = {};
  final Map<String, TextEditingController> _mitigationOwnerCtrls = {};

  @override
  void initState() {
    super.initState();
    _content = PreMortemContent.decode(widget.template.content);
    _goalCtrl = TextEditingController(text: _content.goal);
    _seedCauseControllers();
  }

  @override
  void didUpdateWidget(covariant PreMortemView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = PreMortemContent.decode(widget.template.content);
      _goalCtrl.text = _content.goal;
      _disposeCauseControllers();
      _seedCauseControllers();
    }
  }

  void _seedCauseControllers() {
    for (final cause in _content.causes) {
      _causeDescCtrls.putIfAbsent(
        cause.id,
        () => TextEditingController(text: cause.description),
      );
      for (final m in cause.mitigations) {
        _mitigationDescCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(text: m.description),
        );
        _mitigationOwnerCtrls.putIfAbsent(
          m.id,
          () => _makeOwnerController(m.id, m.owner ?? ''),
        );
      }
    }
  }

  /// Build a controller for a mitigation's owner field that fires the
  /// standard mitigation-update flow on every change — covers both the
  /// user typing into the picker AND the picker writing the chosen
  /// person's name back into the controller after a selection or a
  /// freshly-added Person.
  TextEditingController _makeOwnerController(String mitId, String initial) {
    final ctrl = TextEditingController(text: initial);
    ctrl.addListener(() => _onOwnerTextChanged(mitId, ctrl.text));
    return ctrl;
  }

  /// Looks up the parent cause for [mitId] then routes through the same
  /// patch-content path the description field uses.
  void _onOwnerTextChanged(String mitId, String value) {
    for (final cause in _content.causes) {
      if (cause.mitigations.any((m) => m.id == mitId)) {
        // Skip the no-op case where the controller is being rebuilt
        // with the same value (e.g. didUpdateWidget seeding).
        final current = cause.mitigations
            .firstWhere((m) => m.id == mitId)
            .owner ??
            '';
        if (current == value.trim()) return;
        _onMitigationFieldChanged(
          cause.id,
          mitId,
          (m) => m.copyWith(
              owner: value.trim().isEmpty ? null : value.trim()),
        );
        return;
      }
    }
  }

  void _disposeCauseControllers() {
    for (final c in _causeDescCtrls.values) {
      c.dispose();
    }
    for (final c in _mitigationDescCtrls.values) {
      c.dispose();
    }
    for (final c in _mitigationOwnerCtrls.values) {
      c.dispose();
    }
    _causeDescCtrls.clear();
    _mitigationDescCtrls.clear();
    _mitigationOwnerCtrls.clear();
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    _disposeCauseControllers();
    super.dispose();
  }

  Future<void> _save(PreMortemContent next) async {
    // Update local state AND rebuild — text fields manage their own
    // display via the controllers, but level chips, promoted pills,
    // and the cause/mitigation lists all need a repaint.
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  // ---- Mutations ----------------------------------------------------------

  void _onGoalChanged(String value) {
    final next = _content.copyWith(goal: value);
    _save(next);
  }

  void _addCause() {
    final id = const Uuid().v4();
    final cause = PreMortemCause(id: id);
    final next = _content.copyWith(causes: [..._content.causes, cause]);
    _causeDescCtrls[id] = TextEditingController();
    setState(() {});
    _save(next);
  }

  void _onCauseFieldChanged(
      String causeId, PreMortemCause Function(PreMortemCause) edit) {
    final updated = _content.causes
        .map((c) => c.id == causeId ? edit(c) : c)
        .toList();
    final next = _content.copyWith(causes: updated);
    _save(next);
  }

  void _deleteCause(String causeId) {
    final updated =
        _content.causes.where((c) => c.id != causeId).toList();
    _causeDescCtrls.remove(causeId)?.dispose();
    setState(() {});
    _save(_content.copyWith(causes: updated));
  }

  void _addMitigation(String causeId) {
    final mitId = const Uuid().v4();
    final updated = _content.causes.map((c) {
      if (c.id != causeId) return c;
      return c.copyWith(
        mitigations: [...c.mitigations, PreMortemMitigation(id: mitId)],
      );
    }).toList();
    _mitigationDescCtrls[mitId] = TextEditingController();
    _mitigationOwnerCtrls[mitId] = _makeOwnerController(mitId, '');
    setState(() {});
    _save(_content.copyWith(causes: updated));
  }

  void _onMitigationFieldChanged(
    String causeId,
    String mitigationId,
    PreMortemMitigation Function(PreMortemMitigation) edit,
  ) {
    final updated = _content.causes.map((c) {
      if (c.id != causeId) return c;
      final mits = c.mitigations
          .map((m) => m.id == mitigationId ? edit(m) : m)
          .toList();
      return c.copyWith(mitigations: mits);
    }).toList();
    _save(_content.copyWith(causes: updated));
  }

  void _deleteMitigation(String causeId, String mitigationId) {
    final updated = _content.causes.map((c) {
      if (c.id != causeId) return c;
      return c.copyWith(
        mitigations:
            c.mitigations.where((m) => m.id != mitigationId).toList(),
      );
    }).toList();
    _mitigationDescCtrls.remove(mitigationId)?.dispose();
    _mitigationOwnerCtrls.remove(mitigationId)?.dispose();
    setState(() {});
    _save(_content.copyWith(causes: updated));
  }

  // ---- Promotion ----------------------------------------------------------

  Future<void> _promoteCauseToRisk(PreMortemCause cause) async {
    if (cause.promotedToRiskId != null) return;
    if (cause.description.trim().isEmpty) {
      _snack('Add a description before promoting.');
      return;
    }
    final db = context.read<AppDatabase>();
    final id = const Uuid().v4();
    await db.raidDao.insertRisk(RisksCompanion.insert(
      id: id,
      projectId: widget.template.projectId,
      description: cause.description,
      likelihood: Value(cause.likelihood),
      impact: Value(cause.impact),
      source: const Value('pre_mortem'),
      sourceNote: Value('Pre-mortem: ${widget.template.name}'),
    ));
    _onCauseFieldChanged(
        cause.id, (c) => c.copyWith(promotedToRiskId: id));
    _snack('Cause promoted to Risk.');
  }

  Future<void> _promoteMitigationToAction(
      String causeId, PreMortemMitigation m) async {
    if (m.promotedToActionId != null) return;
    if (m.description.trim().isEmpty) {
      _snack('Add a description before promoting.');
      return;
    }
    final db = context.read<AppDatabase>();
    final id = const Uuid().v4();
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: id,
      projectId: widget.template.projectId,
      description: m.description,
      owner: Value(m.owner),
      source: const Value('pre_mortem'),
      sourceNote: Value('Pre-mortem: ${widget.template.name}'),
    ));
    _onMitigationFieldChanged(
        causeId, m.id, (x) => x.copyWith(promotedToActionId: id));
    _snack('Mitigation promoted to Action.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<Person>>(
      stream: db.peopleDao.watchPersonsForProject(widget.template.projectId),
      builder: (context, snap) {
        final people = snap.data ?? const <Person>[];
        return _buildBody(db, people);
      },
    );
  }

  Widget _buildBody(AppDatabase db, List<Person> people) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            label: 'The Goal',
            hint: 'The imagined failure state. Pick one sentence.',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: KColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: KColors.border),
            ),
            child: TextField(
              controller: _goalCtrl,
              maxLines: null,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 14,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                hintText:
                    'e.g. "The TAC Integration programme failed to '
                    'deliver by September 2026."',
                hintStyle:
                    TextStyle(color: KColors.textMuted, fontSize: 13),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: _onGoalChanged,
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            label: 'How did we get here?',
            hint: 'List plausible causes. Add mitigations under each.',
          ),
          const SizedBox(height: 8),
          if (_content.causes.isEmpty)
            const _EmptyCauses()
          else
            ..._content.causes
                .map((c) => _CauseCard(
                      key: ValueKey(c.id),
                      cause: c,
                      descCtrl: _causeDescCtrls[c.id]!,
                      mitDescCtrls: _mitigationDescCtrls,
                      mitOwnerCtrls: _mitigationOwnerCtrls,
                      people: people,
                      db: db,
                      projectId: widget.template.projectId,
                      onDescChanged: (v) => _onCauseFieldChanged(
                          c.id, (x) => x.copyWith(description: v)),
                      onLikelihoodChanged: (v) => _onCauseFieldChanged(
                          c.id, (x) => x.copyWith(likelihood: v)),
                      onImpactChanged: (v) => _onCauseFieldChanged(
                          c.id, (x) => x.copyWith(impact: v)),
                      onDelete: () => _deleteCause(c.id),
                      onPromote: () => _promoteCauseToRisk(c),
                      onAddMitigation: () => _addMitigation(c.id),
                      onMitDescChanged: (mid, v) => _onMitigationFieldChanged(
                          c.id, mid, (m) => m.copyWith(description: v)),
                      onMitDelete: (mid) => _deleteMitigation(c.id, mid),
                      onMitPromote: (m) =>
                          _promoteMitigationToAction(c.id, m),
                    )),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addCause,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add cause'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KColors.amber,
                side: const BorderSide(color: KColors.amber),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String hint;

  const _SectionHeader({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _EmptyCauses extends StatelessWidget {
  const _EmptyCauses();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'No causes yet. Click "Add cause" below to list the ways '
        'this goal could fail.',
        style: TextStyle(
          color: KColors.textMuted,
          fontSize: 12.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _CauseCard extends StatelessWidget {
  final PreMortemCause cause;
  final TextEditingController descCtrl;
  final Map<String, TextEditingController> mitDescCtrls;
  final Map<String, TextEditingController> mitOwnerCtrls;
  // Project context — threaded down so the owner picker can autocomplete
  // against existing Persons and open AddPersonDialog for new names.
  final List<Person> people;
  final AppDatabase db;
  final String projectId;
  final ValueChanged<String> onDescChanged;
  final ValueChanged<String> onLikelihoodChanged;
  final ValueChanged<String> onImpactChanged;
  final VoidCallback onDelete;
  final VoidCallback onPromote;
  final VoidCallback onAddMitigation;
  final void Function(String mitId, String v) onMitDescChanged;
  final void Function(String mitId) onMitDelete;
  final void Function(PreMortemMitigation m) onMitPromote;

  const _CauseCard({
    super.key,
    required this.cause,
    required this.descCtrl,
    required this.mitDescCtrls,
    required this.mitOwnerCtrls,
    required this.people,
    required this.db,
    required this.projectId,
    required this.onDescChanged,
    required this.onLikelihoodChanged,
    required this.onImpactChanged,
    required this.onDelete,
    required this.onPromote,
    required this.onAddMitigation,
    required this.onMitDescChanged,
    required this.onMitDelete,
    required this.onMitPromote,
  });

  @override
  Widget build(BuildContext context) {
    final isPromoted = cause.promotedToRiskId != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(
          color: isPromoted
              ? KColors.phosphor.withValues(alpha: 0.45)
              : KColors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: descCtrl,
                  maxLines: null,
                  style: const TextStyle(
                    color: KColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'How might this happen?',
                    hintStyle: TextStyle(
                        color: KColors.textMuted, fontSize: 12.5),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: onDescChanged,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Cause actions',
                icon: const Icon(Icons.more_horiz,
                    size: 16, color: KColors.textMuted),
                onSelected: (v) {
                  if (v == 'promote') {
                    onPromote();
                  } else if (v == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => [
                  if (!isPromoted)
                    const PopupMenuItem(
                      value: 'promote',
                      child: Text('Promote to Risk'),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete cause'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Likelihood',
                  style: TextStyle(
                      color: KColors.textMuted, fontSize: 11)),
              const SizedBox(width: 6),
              _LevelChips(
                  value: cause.likelihood, onChanged: onLikelihoodChanged),
              const SizedBox(width: 16),
              const Text('Impact',
                  style: TextStyle(
                      color: KColors.textMuted, fontSize: 11)),
              const SizedBox(width: 6),
              _LevelChips(value: cause.impact, onChanged: onImpactChanged),
              const Spacer(),
              if (isPromoted)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: KColors.phosDim.withValues(alpha: 0.55),
                    border: Border.all(
                        color: KColors.phosphor.withValues(alpha: 0.5),
                        width: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 11, color: KColors.phosphor),
                      SizedBox(width: 4),
                      Text(
                        'Promoted to Risk',
                        style: TextStyle(
                          color: KColors.phosphor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: KColors.border),
          const SizedBox(height: 10),
          const Text(
            'MITIGATIONS',
            style: TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          if (cause.mitigations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No mitigations yet.',
                style: TextStyle(
                  color: KColors.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...cause.mitigations.map((m) {
              return _MitigationRow(
                key: ValueKey(m.id),
                mitigation: m,
                descCtrl: mitDescCtrls[m.id]!,
                ownerCtrl: mitOwnerCtrls[m.id]!,
                people: people,
                db: db,
                projectId: projectId,
                onDescChanged: (v) => onMitDescChanged(m.id, v),
                onDelete: () => onMitDelete(m.id),
                onPromote: () => onMitPromote(m),
              );
            }),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAddMitigation,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add mitigation'),
              style: TextButton.styleFrom(
                foregroundColor: KColors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MitigationRow extends StatelessWidget {
  final PreMortemMitigation mitigation;
  final TextEditingController descCtrl;
  final TextEditingController ownerCtrl;
  final List<Person> people;
  final AppDatabase db;
  final String projectId;
  final ValueChanged<String> onDescChanged;
  final VoidCallback onDelete;
  final VoidCallback onPromote;

  const _MitigationRow({
    super.key,
    required this.mitigation,
    required this.descCtrl,
    required this.ownerCtrl,
    required this.people,
    required this.db,
    required this.projectId,
    required this.onDescChanged,
    required this.onDelete,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final isPromoted = mitigation.promotedToActionId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.arrow_forward,
                size: 12, color: KColors.amber),
          ),
          Expanded(
            child: TextField(
              controller: descCtrl,
              maxLines: null,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12.5,
                height: 1.35,
              ),
              decoration: const InputDecoration(
                hintText: 'How will we prevent this?',
                hintStyle:
                    TextStyle(color: KColors.textMuted, fontSize: 12),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onDescChanged,
            ),
          ),
          const SizedBox(width: 8),
          // Owner picker — wired to the project's Persons table so the
          // user can autocomplete existing names or add a new one. The
          // AddPersonDialog (opened from the dropdown's "Add new"
          // affordance) persists the row in Persons before returning,
          // satisfying the "no free-text owners" rule.
          SizedBox(
            width: 180,
            child: PersonPickerField(
              key: ValueKey('owner-${mitigation.id}'),
              controller: ownerCtrl,
              label: 'Owner',
              persons: people,
              db: db,
              projectId: projectId,
              onPersonCreated: () {},
            ),
          ),
          if (isPromoted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tooltip(
                message: 'Promoted to Action',
                child: Icon(Icons.check_circle,
                    size: 14, color: KColors.phosphor),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Mitigation actions',
            icon: const Icon(Icons.more_horiz,
                size: 14, color: KColors.textMuted),
            onSelected: (v) {
              if (v == 'promote') {
                onPromote();
              } else if (v == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => [
              if (!isPromoted)
                const PopupMenuItem(
                    value: 'promote', child: Text('Promote to Action')),
              const PopupMenuItem(
                  value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _LevelChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String v, String label) {
      final isOn = value == v;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOn
                  ? _colourFor(v).withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isOn ? _colourFor(v) : KColors.border,
                width: 0.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isOn ? _colourFor(v) : KColors.textDim,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('low', 'L'),
        chip('medium', 'M'),
        chip('high', 'H'),
      ],
    );
  }

  Color _colourFor(String level) {
    switch (level) {
      case 'low':
        return KColors.phosphor;
      case 'medium':
        return KColors.amber;
      case 'high':
        return KColors.red;
      default:
        return KColors.textDim;
    }
  }
}

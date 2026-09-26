import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/raid_assist_prompts.dart';
import '../../core/raid/dependency_plan_link.dart';
import '../../core/raid/dependency_timeline.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../core/raid/raid_lifecycle.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/ai_assist_button.dart';
import '../../shared/widgets/detail_dialog.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import '../../shared/widgets/plan_activity_picker.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../journal/journal_source_link.dart';
import '../raid/dependency_slack_chip.dart';
import '../raid/raid_links_section.dart';

class DecisionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Decision? decision;
  final bool startInViewMode;

  const DecisionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.decision,
    this.startInViewMode = false,
  });

  @override
  State<DecisionFormDialog> createState() => _DecisionFormDialogState();
}

class _DecisionFormDialogState extends State<DecisionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _decisionMakerCtrl;
  late TextEditingController _rationaleCtrl;
  late TextEditingController _optionsCtrl;
  late TextEditingController _impactCtrl;
  late TextEditingController _outcomeCtrl;
  late TextEditingController _sourceNoteCtrl;
  String? _dueDate;
  String? _decidedAt;
  String? _planActivityId;
  bool _showOnPlan = false;

  String _status = 'pending';
  String _source = 'manual';

  late bool _isViewing;
  List<Person> _persons = [];
  List<TimelineWorkPackage> _workPackages = const [];
  List<TimelineActivity> _activities = const [];
  String? _month0Date;

  // 'decided' is what the journal parser writes; the rest are the
  // governance outcomes. Both vocabularies live in the register.
  final _statuses = [
    'pending', 'decided', 'approved', 'rejected', 'deferred', 'closed'
  ];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];

  bool get _isEdit => widget.decision != null;

  @override
  void initState() {
    super.initState();
    final d = widget.decision;
    _descCtrl = TextEditingController(text: d?.description ?? '');
    _decisionMakerCtrl = TextEditingController(text: d?.decisionMaker ?? '');
    _rationaleCtrl = TextEditingController(text: d?.rationale ?? '');
    _optionsCtrl = TextEditingController(text: d?.optionsConsidered ?? '');
    _impactCtrl = TextEditingController(text: d?.impactStatement ?? '');
    _outcomeCtrl = TextEditingController(text: d?.outcome ?? '');
    _sourceNoteCtrl = TextEditingController(text: d?.sourceNote ?? '');
    _dueDate = d?.dueDate;
    _decidedAt = d?.decidedAt;
    _planActivityId = d?.planActivityId;
    _status = d?.status ?? 'pending';
    _source = d?.source ?? 'manual';
    _isViewing = widget.startInViewMode && d != null;
    _load();
  }

  Future<void> _loadPersons() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  Future<void> _load() async {
    final db = widget.db;
    final persons = await db.peopleDao.getPersonsForProject(widget.projectId);
    final wps = await db.programmeGanttDao.getWorkPackages(widget.projectId);
    final acts =
        await db.programmeGanttDao.getActivitiesForProject(widget.projectId);
    final header = await db.programmeGanttDao.getHeader(widget.projectId);
    final planRow = widget.decision != null
        ? await DependencyPlanLink.find(
            db, widget.projectId, widget.decision!.id,
            kind: PlanLinkKind.decision)
        : null;
    if (!mounted) return;
    setState(() {
      _persons = persons;
      _workPackages = wps;
      _activities = acts;
      _month0Date = header?.month0Date;
      _showOnPlan = planRow != null;
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _decisionMakerCtrl.dispose();
    _rationaleCtrl.dispose();
    _optionsCtrl.dispose();
    _impactCtrl.dispose();
    _outcomeCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _onStatusChanged(String? v) {
    if (v == null) return;
    setState(() {
      _status = v;
      // First move into a "made" state stamps today as the decided-on
      // date; the PM can still change it.
      if (kDecisionMadeStatuses.contains(v) && _decidedAt == null) {
        _decidedAt = du.toIsoDate(DateTime.now());
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.decision == null;
    final existing =
        await widget.db.decisionsDao.getDecisionsForProject(widget.projectId);
    final nums = existing
        .where((d) => d.ref != null && d.ref!.startsWith('DC'))
        .map((d) => int.tryParse(d.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    final String ref =
        widget.decision?.ref ?? 'DC${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.decision?.id ?? const Uuid().v4();
    final description = _descCtrl.text.trim();
    await widget.db.decisionsDao.upsertDecision(
      DecisionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(description),
        status: Value(_status),
        decisionMaker: Value(_trimOrNull(_decisionMakerCtrl)),
        dueDate: Value(_dueDate),
        decidedAt: Value(_decidedAt),
        rationale: Value(_trimOrNull(_rationaleCtrl)),
        optionsConsidered: Value(_trimOrNull(_optionsCtrl)),
        impactStatement: Value(_trimOrNull(_impactCtrl)),
        outcome: Value(_trimOrNull(_outcomeCtrl)),
        planActivityId: Value(_planActivityId),
        source: Value(_source),
        sourceNote: Value(_trimOrNull(_sourceNoteCtrl)),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await DependencyPlanLink.sync(
      widget.db,
      projectId: widget.projectId,
      dependencyId: id,
      ref: ref,
      description: description,
      dependencyType: 'inbound', // a pending decision gates the start
      activityId: _planActivityId,
      // Once made, the decision no longer gates anything — the arrow
      // comes off the Gantt. Reopening needs the tick again.
      show: _showOnPlan && !kDecisionMadeStatuses.contains(_status),
      kind: PlanLinkKind.decision,
    );

    if (isNew && mounted) {
      context.analytics.track(
        KeelEvents.decisionCreated,
        props: {KeelEventProps.source: 'decision_form'},
      );
    }
    // Cascade to linked programmes; the service decides per link
    // (full detail vs escalated only) so no flag check here.
    if (mounted) {
      final fresh = await widget.db.decisionsDao.getDecisionById(id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushDecision(fresh);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── Timeline ───────────────────────────────────────────────────────────────

  TimelineActivity? get _activity => _planActivityId == null
      ? null
      : _activities.where((a) => a.id == _planActivityId).firstOrNull;

  String? get _activityLabel => _planActivityId == null
      ? null
      : PlanActivityPicker.labelFor(_planActivityId!,
          workPackages: _workPackages, activities: _activities);

  DependencySlack? get _slack {
    final a = _activity;
    if (a == null) return null;
    return dependencySlack(
      dueDate: _dueDate,
      dependencyType: 'inbound',
      activityStartDate: a.startDate,
      activityEndDate: a.endDate,
      activityStartMonth: a.startMonth,
      activityEndMonth: a.endMonth,
      month0Date: _month0Date,
    );
  }

  Widget _timelineSummary({required bool editable}) {
    final a = _activity;
    final slack = _slack;
    if (a == null) {
      return const Text(
        'Not linked to a plan activity — the register can\'t tell whether '
        'a late decision threatens the schedule.',
        style: TextStyle(color: KColors.textMuted, fontSize: 11),
      );
    }
    // Once the call is made the activity is no longer gated — a slack
    // chip would read as a live schedule threat, so say what happened.
    final made = kDecisionMadeStatuses.contains(_status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!editable) DetailField('Plan activity waiting on this', _activityLabel),
        if (made)
          Row(children: [
            const Icon(Icons.check_circle, size: 12, color: KColors.phosphor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _decidedAt != null
                    ? 'Decided on ${du.formatDate(_decidedAt)} — no longer '
                        'holding up the activity. The plan arrow is removed '
                        'while decided.'
                    : 'Decided — no longer holding up the activity. The plan '
                        'arrow is removed while decided.',
                style: const TextStyle(color: KColors.phosphor, fontSize: 11),
              ),
            ),
          ])
        else if (slack != null)
          DependencySlackChip(slack: slack)
        else
          Text(
            _dueDate == null
                ? 'Set a needed-by date to see the slack against the plan.'
                : 'The linked activity has no dates yet.',
            style: const TextStyle(color: KColors.textMuted, fontSize: 11),
          ),
        if (!made) ...[
          const SizedBox(height: 6),
          const Text(
            'Measured against the activity\'s start: it can\'t begin until '
            'this is decided.',
            style: TextStyle(color: KColors.textMuted, fontSize: 10),
          ),
        ],
      ],
    );
  }

  // ── AI assist ──────────────────────────────────────────────────────────────

  Future<RaidAssistPrompt> _prompt(DecisionAssistField field) async {
    final ctx =
        await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
    return decisionAssistPrompt(
      field: field,
      description: _descCtrl.text,
      status: _status,
      decisionMaker: _decisionMakerCtrl.text,
      dueDate: _dueDate,
      rationale: _rationaleCtrl.text,
      optionsConsidered: _optionsCtrl.text,
      impactStatement: _impactCtrl.text,
      outcome: _outcomeCtrl.text,
      linkedActivity: _activityLabel,
      projectContext: ctx,
    );
  }

  Color get _accent => switch (_status) {
        'pending' => KColors.blue,
        'decided' || 'approved' => KColors.phosphor,
        'rejected' => KColors.red,
        _ => KColors.textMuted,
      };

  // ── Read view ──────────────────────────────────────────────────────────────

  Widget _readView() {
    final d = widget.decision!;
    return DetailDialog(
      accent: _accent,
      title: [
        if (d.ref != null) ...[DetailRefChip(d.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Decision')),
        Text(d.status.toUpperCase(),
            style: TextStyle(
                color: _accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
      left: [
        DetailField('Decision required', d.description, large: true),
        Row(
          children: [
            Expanded(child: DetailField('Status', d.status)),
            if (d.decisionMaker != null && d.decisionMaker!.isNotEmpty)
              Expanded(child: DetailField('Decision maker', d.decisionMaker)),
          ],
        ),
        Row(
          children: [
            if (d.dueDate != null)
              Expanded(
                  child: DetailField('Needed by', du.formatDate(d.dueDate))),
            if (d.decidedAt != null)
              Expanded(
                  child: DetailField('Decided on', du.formatDate(d.decidedAt))),
          ],
        ),
        DetailField('Options considered', d.optionsConsidered),
        DetailField('Rationale', d.rationale),
        DetailField('Outcome', d.outcome),
      ],
      right: [
        DetailField('Impact of leaving it open', d.impactStatement),
        const DetailSectionLabel('Timeline'),
        const SizedBox(height: 8),
        _timelineSummary(editable: false),
        if (_showOnPlan) ...[
          const SizedBox(height: 6),
          const Row(children: [
            Icon(Icons.timeline, size: 12, color: KColors.textDim),
            SizedBox(width: 4),
            Text('Shown on the plan as an external dependency',
                style: TextStyle(color: KColors.textDim, fontSize: 10)),
          ]),
        ],
        const DetailDivider(),
        Row(
          children: [
            Expanded(child: DetailField('Source', d.source)),
            if (d.sourceNote != null && d.sourceNote!.isNotEmpty)
              Expanded(child: DetailField('Source Note', d.sourceNote)),
          ],
        ),
        JournalSourceLink(
          db: widget.db,
          projectId: widget.projectId,
          itemId: d.id,
          itemText: d.description,
        ),
        DetailField(
            'Last updated', du.formatDate(d.updatedAt.toIso8601String())),
        RaidLinksSection(
          db: widget.db,
          projectId: widget.projectId,
          itemType: RaidKind.decision,
          itemId: d.id,
          readOnly: true,
        ),
      ],
      footer: [
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Edit view ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = _isEdit;

    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.decision?.ref != null) ...[
          DetailRefChip(widget.decision!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(
            child: DetailTitle(isEdit ? 'Edit Decision' : 'New Decision')),
      ],
      left: [
        TextFormField(
          controller: _descCtrl,
          autofocus: !isEdit,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Decision required *',
            hintText: 'The question that needs an answer, e.g. "Which '
                'vendor for the payments gateway?"',
            alignLabelWithHint: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownField(
                label: 'Status',
                value: _status,
                items: _statuses,
                onChanged: _onStatusChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PersonPickerField(
                controller: _decisionMakerCtrl,
                label: 'Decision maker',
                persons: _persons,
                db: widget.db,
                projectId: widget.projectId,
                onPersonCreated: _loadPersons,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DatePickerField(
                label: 'Needed by',
                isoValue: _dueDate,
                onChanged: (v) => setState(() => _dueDate = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DatePickerField(
                label: 'Decided on',
                isoValue: _decidedAt,
                onChanged: (v) => setState(() => _decidedAt = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AiAssistedLabel(
          label: 'Options considered',
          target: _optionsCtrl,
          tooltip: 'Draft the realistic alternatives, including doing nothing',
          buildPrompt: () => _prompt(DecisionAssistField.optionsConsidered),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _optionsCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'The alternatives weighed, one per line, with the '
                'main trade-off of each',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        AiAssistedLabel(
          label: 'Rationale',
          target: _rationaleCtrl,
          tooltip: 'Draft why this is (or will be) the right call',
          buildPrompt: () => _prompt(DecisionAssistField.rationale),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _rationaleCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'The drivers, constraints and trade-offs that settle it',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _outcomeCtrl,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Outcome',
            hintText: 'What was decided, once it is',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
      ],
      right: [
        AiAssistedLabel(
          label: 'Impact of leaving it open',
          target: _impactCtrl,
          tooltip: 'Draft what is blocked or at risk while this stays undecided',
          buildPrompt: () => _prompt(DecisionAssistField.impactStatement),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _impactCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'What can\'t proceed, which milestones move, and by '
                'when it must be decided',
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        const DetailSectionLabel('Timeline'),
        const SizedBox(height: 8),
        if (_workPackages.isEmpty)
          const Text(
            'No plan yet — build work packages and activities in Plan to '
            'link this decision to the schedule.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11),
          )
        else
          PlanActivityPicker(
            value: _planActivityId,
            workPackages: _workPackages,
            activities: _activities,
            label: 'Plan activity waiting on this decision',
            onChanged: (v) => setState(() {
              _planActivityId = v;
              if (v == null) _showOnPlan = false;
            }),
          ),
        const SizedBox(height: 10),
        _timelineSummary(editable: true),
        if (_planActivityId != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _showOnPlan,
                onChanged: (v) => setState(() => _showOnPlan = v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.timeline, size: 13, color: KColors.blue),
            const SizedBox(width: 5),
            const Expanded(
              child: Text(
                'Show on the plan as an external dependency arrow into '
                'this activity',
                style: TextStyle(color: KColors.text, fontSize: 12),
              ),
            ),
          ]),
        ],
        const DetailDivider(),
        Row(
          children: [
            Expanded(
              child: DropdownField(
                label: 'Source',
                value: _source,
                items: _sources,
                onChanged: (v) => setState(() => _source = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _sourceNoteCtrl,
                decoration: const InputDecoration(labelText: 'Source Note'),
              ),
            ),
          ],
        ),
        if (isEdit) ...[
          const SizedBox(height: 12),
          JournalSourceLink(
            db: widget.db,
            projectId: widget.projectId,
            itemId: widget.decision!.id,
            itemText: widget.decision!.description,
          ),
          const DetailDivider(),
          RaidLinksSection(
            db: widget.db,
            projectId: widget.projectId,
            itemType: RaidKind.decision,
            itemId: widget.decision!.id,
          ),
        ],
        const SizedBox(height: 12),
      ],
      footer: [
        const Spacer(),
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create',
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

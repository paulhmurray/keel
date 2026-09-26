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
import 'dependency_slack_chip.dart';
import 'raid_convert_button.dart';
import '../journal/journal_source_link.dart';
import 'raid_links_section.dart';

const kDependencyTypeLabels = {
  'inbound': 'Inbound — we need something from them',
  'outbound': 'Outbound — they need something from us',
  'bilateral': 'Bilateral — each side needs the other',
};

class DependencyFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProgramDependency? dependency;
  final bool startInViewMode;

  const DependencyFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.dependency,
    this.startInViewMode = false,
  });

  @override
  State<DependencyFormDialog> createState() => _DependencyFormDialogState();
}

class _DependencyFormDialogState extends State<DependencyFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _counterpartyCtrl;
  late TextEditingController _rationaleCtrl;
  late TextEditingController _impactCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _sourceNoteCtrl;
  String? _dueDate;
  String? _planActivityId;
  bool _showOnPlan = false;

  String _dependencyType = 'inbound';
  String _status = 'open';
  String _source = 'manual';
  List<Person> _persons = const [];
  List<TimelineWorkPackage> _workPackages = const [];
  List<TimelineActivity> _activities = const [];
  String? _month0Date;

  late bool _isViewing;

  final _types = ['inbound', 'outbound', 'bilateral'];
  final _statuses = ['open', 'in progress', 'resolved', 'closed', 'blocked'];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];

  bool get _isEdit => widget.dependency != null;

  @override
  void initState() {
    super.initState();
    final d = widget.dependency;
    _descCtrl = TextEditingController(text: d?.description ?? '');
    _counterpartyCtrl = TextEditingController(text: d?.counterparty ?? '');
    _rationaleCtrl = TextEditingController(text: d?.rationale ?? '');
    _impactCtrl = TextEditingController(text: d?.impactStatement ?? '');
    _ownerCtrl = TextEditingController(text: d?.owner ?? '');
    _dueDate = d?.dueDate;
    _planActivityId = d?.planActivityId;
    _sourceNoteCtrl = TextEditingController(text: d?.sourceNote ?? '');
    _dependencyType = d?.dependencyType ?? 'inbound';
    _status = d?.status ?? 'open';
    _source = d?.source ?? 'manual';
    _isViewing = widget.startInViewMode && d != null;
    _load();
  }

  Future<void> _loadPersons() async {
    final list =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = list);
  }

  Future<void> _load() async {
    final db = widget.db;
    final persons = await db.peopleDao.getPersonsForProject(widget.projectId);
    final wps = await db.programmeGanttDao.getWorkPackages(widget.projectId);
    final acts =
        await db.programmeGanttDao.getActivitiesForProject(widget.projectId);
    final header = await db.programmeGanttDao.getHeader(widget.projectId);
    final planRow = widget.dependency != null
        ? await DependencyPlanLink.find(
            db, widget.projectId, widget.dependency!.id)
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
    _counterpartyCtrl.dispose();
    _rationaleCtrl.dispose();
    _impactCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.dependency == null;
    final existing = await widget.db.raidDao.getDependenciesForProject(widget.projectId);
    final nums = existing
        .where((d) => d.ref != null && d.ref!.startsWith('D'))
        .map((d) => int.tryParse(d.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    final String ref = widget.dependency?.ref ??
        'D${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.dependency?.id ?? const Uuid().v4();
    final description = _descCtrl.text.trim();
    await widget.db.raidDao.upsertDependency(
      ProgramDependenciesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(description),
        dependencyType: Value(_dependencyType),
        counterparty: Value(_trimOrNull(_counterpartyCtrl)),
        rationale: Value(_trimOrNull(_rationaleCtrl)),
        impactStatement: Value(_trimOrNull(_impactCtrl)),
        planActivityId: Value(_planActivityId),
        owner: Value(_trimOrNull(_ownerCtrl)),
        status: Value(_status),
        closedAt: Value(nextClosedAt(
            kind: RaidKind.dependency,
            newStatus: _status,
            existing: widget.dependency?.closedAt)),
        dueDate: Value(_dueDate),
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
      dependencyType: _dependencyType,
      activityId: _planActivityId,
      // A closed dependency no longer gates anything — the arrow comes
      // off the Gantt. Reopening needs the tick again.
      show: _showOnPlan && !isTerminalStatus(RaidKind.dependency, _status),
    );

    if (isNew && mounted) {
      context.analytics.track(
        KeelEvents.dependencyCreated,
        props: {KeelEventProps.source: 'dependency_form'},
      );
    }
    // Cascade to linked programmes; the service decides per link
    // (full detail vs escalated only) so no flag check here.
    if (mounted) {
      final fresh = await widget.db.raidDao.getDependencyById(id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushDependency(fresh);
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

  DependencySlack? _slack({required String? dueDate, required String type}) {
    final a = _activity;
    if (a == null) return null;
    return dependencySlack(
      dueDate: dueDate,
      dependencyType: type,
      activityStartDate: a.startDate,
      activityEndDate: a.endDate,
      activityStartMonth: a.startMonth,
      activityEndMonth: a.endMonth,
      month0Date: _month0Date,
    );
  }

  /// One-line explanation of what linking to the plan means for this
  /// direction, so the PM knows which date the slack is measured to.
  String _timelineHint(String type) => switch (type) {
        'outbound' =>
          'Measured against the activity\'s end: we must deliver by then.',
        _ =>
          'Measured against the activity\'s start: it can\'t begin until '
              'this lands.',
      };

  Widget _timelineSummary({required bool editable}) {
    final a = _activity;
    final slack = _slack(dueDate: _dueDate, type: _dependencyType);
    if (a == null) {
      return const Text(
        'Not linked to a plan activity — the register can\'t tell whether '
        'this dependency threatens the schedule.',
        style: TextStyle(color: KColors.textMuted, fontSize: 11),
      );
    }
    final closed = isTerminalStatus(RaidKind.dependency, _status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!editable) DetailField('Gates plan activity', _activityLabel),
        if (closed)
          const Row(children: [
            Icon(Icons.check_circle, size: 12, color: KColors.phosphor),
            SizedBox(width: 5),
            Flexible(
              child: Text(
                'Closed — no longer holding up the activity. The plan '
                'arrow is removed while closed.',
                style: TextStyle(color: KColors.phosphor, fontSize: 11),
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
        if (!closed) ...[
          const SizedBox(height: 6),
          Text(_timelineHint(_dependencyType),
              style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
        ],
      ],
    );
  }

  // ── AI assist ──────────────────────────────────────────────────────────────

  Future<RaidAssistPrompt> _prompt(DependencyAssistField field) async {
    final ctx =
        await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
    return dependencyAssistPrompt(
      field: field,
      description: _descCtrl.text,
      dependencyType: _dependencyType,
      counterparty: _counterpartyCtrl.text,
      rationale: _rationaleCtrl.text,
      impactStatement: _impactCtrl.text,
      owner: _ownerCtrl.text,
      dueDate: _dueDate,
      linkedActivity: _activityLabel,
      projectContext: ctx,
    );
  }

  static const _accent = KColors.blue;

  // ── Read view ──────────────────────────────────────────────────────────────

  Widget _readView() {
    final d = widget.dependency!;
    return DetailDialog(
      accent: _accent,
      title: [
        if (d.ref != null) ...[DetailRefChip(d.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Dependency')),
        Text(d.dependencyType.toUpperCase(),
            style: const TextStyle(
                color: _accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
      left: [
        DetailField('Description', d.description, large: true),
        Row(
          children: [
            Expanded(
                child: DetailField(
                    'Direction', kDependencyTypeLabels[d.dependencyType])),
            Expanded(child: DetailField('Status', d.status)),
          ],
        ),
        Row(
          children: [
            if (d.counterparty != null && d.counterparty!.isNotEmpty)
              Expanded(child: DetailField('Counterparty', d.counterparty)),
            if (d.owner != null && d.owner!.isNotEmpty)
              Expanded(child: DetailField('Owner (our side)', d.owner)),
            if (d.dueDate != null)
              Expanded(
                  child: DetailField('Needed by', du.formatDate(d.dueDate))),
            if (isTerminalStatus(RaidKind.dependency, d.status))
              Expanded(
                  child: DetailField(
                      'Closed on',
                      du.formatDate(d.closedAt ??
                          d.updatedAt.toIso8601String().substring(0, 10)))),
          ],
        ),
        DetailField('Why this is a dependency', d.rationale),
        DetailField('Impact if it slips', d.impactStatement),
      ],
      right: [
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
          itemType: RaidKind.dependency,
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
    final canShowOnPlan = _planActivityId != null &&
        DependencyPlanLink.canShowOnPlan(_dependencyType);

    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.dependency?.ref != null) ...[
          DetailRefChip(widget.dependency!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(
            child: DetailTitle(isEdit ? 'Edit Dependency' : 'New Dependency')),
        if (isEdit)
          RaidConvertButton(
            db: widget.db,
            from: RaidKind.dependency,
            itemId: widget.dependency!.id,
            itemRef: widget.dependency!.ref,
            sourceProjectId: widget.dependency!.sourceProjectId,
          ),
      ],
      left: [
        TextFormField(
          controller: _descCtrl,
          autofocus: !isEdit,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Description *',
            hintText: 'What is needed, e.g. "Vendor delivers signed API '
                'contract"',
            alignLabelWithHint: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownField(
                label: 'Direction',
                value: _dependencyType,
                items: _types,
                labelOverrides: kDependencyTypeLabels,
                // Long labels; clip rather than overflow the column.
                isExpanded: true,
                onChanged: (v) => setState(() => _dependencyType = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownField(
                label: 'Status',
                value: _status,
                items: _statuses,
                onChanged: (v) => setState(() => _status = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _counterpartyCtrl,
          decoration: InputDecoration(
            labelText: _dependencyType == 'outbound'
                ? 'Counterparty — who needs it from us'
                : 'Counterparty — who we depend on',
            hintText: 'Team, vendor, programme or system',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PersonPickerField(
                controller: _ownerCtrl,
                label: 'Owner (our side)',
                persons: _persons,
                db: widget.db,
                projectId: widget.projectId,
                onPersonCreated: _loadPersons,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DatePickerField(
                label: 'Needed by',
                isoValue: _dueDate,
                onChanged: (v) => setState(() => _dueDate = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
      ],
      right: [
        const DetailSectionLabel('Timeline'),
        const SizedBox(height: 8),
        if (_workPackages.isEmpty)
          const Text(
            'No plan yet — build work packages and activities in Plan to '
            'link this dependency to the schedule.',
            style: TextStyle(color: KColors.textMuted, fontSize: 11),
          )
        else
          PlanActivityPicker(
            value: _planActivityId,
            workPackages: _workPackages,
            activities: _activities,
            label: _dependencyType == 'outbound'
                ? 'Plan activity that produces it'
                : 'Plan activity that needs it',
            onChanged: (v) => setState(() {
              _planActivityId = v;
              if (v == null) _showOnPlan = false;
            }),
          ),
        const SizedBox(height: 10),
        _timelineSummary(editable: true),
        if (canShowOnPlan) ...[
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
        AiAssistedLabel(
          label: 'Why this is a dependency',
          target: _rationaleCtrl,
          tooltip: 'Draft what we need, why the work can\'t proceed without '
              'it, and the timing assumption',
          buildPrompt: () => _prompt(DependencyAssistField.rationale),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _rationaleCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'What we need from them, and why our work is blocked '
                'until it lands',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        AiAssistedLabel(
          label: 'Impact if it slips',
          target: _impactCtrl,
          tooltip: 'Draft what happens to the plan if this is late or never '
              'lands',
          buildPrompt: () => _prompt(DependencyAssistField.impactStatement),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _impactCtrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Which activities or milestones move, by how much, '
                'and any fallback',
            isDense: true,
          ),
        ),
        if (isEdit) ...[
          const SizedBox(height: 12),
          JournalSourceLink(
            db: widget.db,
            projectId: widget.projectId,
            itemId: widget.dependency!.id,
            itemText: widget.dependency!.description,
          ),
          const DetailDivider(),
          RaidLinksSection(
            db: widget.db,
            projectId: widget.projectId,
            itemType: RaidKind.dependency,
            itemId: widget.dependency!.id,
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

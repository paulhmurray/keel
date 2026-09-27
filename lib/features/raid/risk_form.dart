import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/raid_assist_prompts.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../core/raid/raid_lifecycle.dart';
import '../../core/raid/risk_rating.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/ai_assist_button.dart';
import '../../shared/widgets/raid_quality_hints.dart';
import '../../core/raid/raid_statements.dart';
import '../../shared/widgets/detail_dialog.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../journal/journal_source_link.dart';
import 'raid_convert_button.dart';
import 'raid_links_section.dart';

/// Risk dialog in the register's Planview shape: title and statement,
/// current and target rating on the 5-level scale with a live score,
/// strategy, treatment plan, owner and assignee, escalation flag, review
/// cadence and a status note.
class RiskFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Risk? risk;
  final bool startInViewMode;

  const RiskFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.risk,
    this.startInViewMode = false,
  });

  @override
  State<RiskFormDialog> createState() => _RiskFormDialogState();
}

class _RiskFormDialogState extends State<RiskFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _mitigationCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _assigneeCtrl;
  late TextEditingController _sourceNoteCtrl;
  late TextEditingController _likelihoodWhyCtrl;
  late TextEditingController _impactWhyCtrl;
  late TextEditingController _closureNoteCtrl;
  late TextEditingController _statusNoteCtrl;
  late TextEditingController _enterpriseLinkCtrl;

  String _likelihood = 'possible';
  String _impact = 'moderate';
  String? _likelihoodTarget;
  String? _impactTarget;
  String _strategy = 'treat';
  bool _steerco = false;
  String? _dueDate;
  String? _lastReviewedAt;
  String? _nextReviewAt;
  String _status = 'open';
  String _source = 'manual';
  List<Person> _persons = const [];

  late bool _isViewing;

  final _statuses = ['open', 'in progress', 'closed', 'accepted'];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];

  bool get _isEdit => widget.risk != null;

  @override
  void initState() {
    super.initState();
    final r = widget.risk;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _mitigationCtrl = TextEditingController(text: r?.mitigation ?? '');
    _ownerCtrl = TextEditingController(text: r?.owner ?? '');
    _assigneeCtrl = TextEditingController(text: r?.assignee ?? '');
    _sourceNoteCtrl = TextEditingController(text: r?.sourceNote ?? '');
    _likelihoodWhyCtrl =
        TextEditingController(text: r?.likelihoodRationale ?? '');
    _impactWhyCtrl = TextEditingController(text: r?.impactRationale ?? '');
    _closureNoteCtrl = TextEditingController(text: r?.closureNote ?? '');
    _statusNoteCtrl = TextEditingController(text: r?.statusNote ?? '');
    _enterpriseLinkCtrl =
        TextEditingController(text: r?.enterpriseRiskLink ?? '');
    _likelihood = normaliseLikelihood(r?.likelihood);
    _impact = normaliseConsequence(r?.impact);
    _likelihoodTarget = r?.likelihoodTarget == null
        ? null
        : normaliseLikelihood(r!.likelihoodTarget);
    _impactTarget =
        r?.impactTarget == null ? null : normaliseConsequence(r!.impactTarget);
    _strategy = kRiskStrategies.contains(r?.strategy) ? r!.strategy : 'treat';
    _steerco = r?.steerco ?? false;
    _dueDate = r?.dueDate;
    _lastReviewedAt = r?.lastReviewedAt;
    _nextReviewAt = r?.nextReviewAt;
    _status = r?.status ?? 'open';
    _source = r?.source ?? 'manual';
    _isViewing = widget.startInViewMode && r != null;
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final list = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = list);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _mitigationCtrl.dispose();
    _ownerCtrl.dispose();
    _assigneeCtrl.dispose();
    _sourceNoteCtrl.dispose();
    _likelihoodWhyCtrl.dispose();
    _impactWhyCtrl.dispose();
    _closureNoteCtrl.dispose();
    _statusNoteCtrl.dispose();
    _enterpriseLinkCtrl.dispose();
    super.dispose();
  }

  String _nextRef(List<Risk> existing) {
    final nums = existing
        .where((r) => r.ref != null && r.ref!.startsWith('R'))
        .map((r) {
          final n = int.tryParse(r.ref!.substring(1));
          return n ?? 0;
        })
        .toList();
    nums.sort();
    return 'R${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  String? _trimOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _reviewedToday() {
    final today = DateTime.now();
    setState(() {
      _lastReviewedAt = du.toIsoDate(today);
      _nextReviewAt = nextReviewFrom(today);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.risk == null;
    final String ref = widget.risk?.ref ??
        _nextRef(await widget.db.raidDao.getRisksForProject(widget.projectId));

    final id = widget.risk?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertRisk(
      RisksCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        title: Value(_trimOrNull(_titleCtrl)),
        description: Value(_descCtrl.text.trim()),
        likelihood: Value(_likelihood),
        impact: Value(_impact),
        likelihoodTarget: Value(_likelihoodTarget),
        impactTarget: Value(_impactTarget),
        likelihoodRationale: Value(_trimOrNull(_likelihoodWhyCtrl)),
        impactRationale: Value(_trimOrNull(_impactWhyCtrl)),
        mitigation: Value(_trimOrNull(_mitigationCtrl)),
        strategy: Value(_strategy),
        owner: Value(_trimOrNull(_ownerCtrl)),
        assignee: Value(_trimOrNull(_assigneeCtrl)),
        steerco: Value(_steerco),
        enterpriseRiskLink: Value(_trimOrNull(_enterpriseLinkCtrl)),
        dueDate: Value(_dueDate),
        lastReviewedAt: Value(_lastReviewedAt),
        nextReviewAt: Value(_nextReviewAt),
        statusNote: Value(_trimOrNull(_statusNoteCtrl)),
        status: Value(_status),
        closedAt: Value(nextClosedAt(
            kind: RaidKind.risk,
            newStatus: _status,
            existing: widget.risk?.closedAt)),
        closureNote: Value(_trimOrNull(_closureNoteCtrl)),
        source: Value(_source),
        sourceNote: Value(_trimOrNull(_sourceNoteCtrl)),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (isNew && mounted) {
      context.analytics.track(
        KeelEvents.riskCreated,
        props: {KeelEventProps.source: 'risk_form'},
      );
    }
    // Cascade to linked programmes; the service decides per link
    // (full detail vs escalated only) so no flag check here.
    if (mounted) {
      final fresh = await widget.db.raidDao.getRiskById(id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushRisk(fresh);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── AI assist ──────────────────────────────────────────────────────────────

  Future<RaidAssistPrompt> _prompt(RiskAssistField field) async {
    final ctx =
        await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
    return riskAssistPrompt(
      field: field,
      description: _titleCtrl.text.trim().isEmpty
          ? _descCtrl.text
          : '${_titleCtrl.text.trim()} — ${_descCtrl.text}',
      likelihood: likelihoodLabel(_likelihood),
      impact: consequenceLabel(_impact),
      likelihoodRationale: _likelihoodWhyCtrl.text,
      impactRationale: _impactWhyCtrl.text,
      mitigation: _mitigationCtrl.text,
      owner: _ownerCtrl.text,
      projectContext: ctx,
    );
  }

  Color _bandColor(String band) => switch (band) {
        'high' => KColors.red,
        'medium' => KColors.amber,
        _ => KColors.phosphor,
      };

  Color get _accent => _bandColor(riskBand(_likelihood, _impact));

  /// "Likely / Major · 16" chip coloured by band.
  Widget _scoreChip(String likelihood, String consequence, {String? prefix}) {
    final c = _bandColor(riskBand(likelihood, consequence));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        border: Border.all(color: c.withAlpha(140)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${prefix ?? ''}${likelihoodLabel(likelihood)} / '
        '${consequenceLabel(consequence)} · '
        '${riskScore(likelihood, consequence)}',
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── Read view ──────────────────────────────────────────────────────────────

  Widget _readView() {
    final r = widget.risk!;
    final hasTitle = r.title != null && r.title!.isNotEmpty;
    final terminal = isTerminalStatus(RaidKind.risk, r.status);
    final overdueReview = reviewOverdue(r.nextReviewAt, DateTime.now());
    return DetailDialog(
      accent: _accent,
      title: [
        if (r.ref != null) ...[DetailRefChip(r.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Risk')),
        if (r.steerco) ...[
          const Tooltip(
            message: 'Escalated for attention — how and where it is raised '
                'is the PM\'s call',
            child: Text('▲ ESCALATED',
                style: TextStyle(
                    color: KColors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
          ),
          const SizedBox(width: 10),
        ],
        _scoreChip(r.likelihood, r.impact),
      ],
      left: [
        if (hasTitle) DetailField('Risk', r.title, large: true),
        DetailField('Description', r.description, large: !hasTitle),
        Row(children: [
          Expanded(
              child: DetailField('Likelihood (current)',
                  likelihoodLabel(r.likelihood))),
          Expanded(
              child: DetailField(
                  'Consequence (current)', consequenceLabel(r.impact))),
          Expanded(child: DetailField('Status', r.status)),
        ]),
        DetailField('Why this likelihood', r.likelihoodRationale),
        DetailField('Why this consequence', r.impactRationale),
        Row(children: [
          Expanded(
              child: DetailField(
                  'Strategy',
                  kRiskStrategyLabels[r.strategy]?.split(' — ').first ??
                      r.strategy)),
          if (r.likelihoodTarget != null || r.impactTarget != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TARGET RATING',
                        style: TextStyle(
                            color: KColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 4),
                    _scoreChip(r.likelihoodTarget ?? r.likelihood,
                        r.impactTarget ?? r.impact),
                  ],
                ),
              ),
            ),
        ]),
        DetailField('Treatment plan', r.mitigation),
        if (terminal)
          DetailField(
              r.status == 'accepted' ? 'Accepted on' : 'Closed on',
              du.formatDate(r.closedAt ??
                  r.updatedAt.toIso8601String().substring(0, 10))),
        DetailField(
            r.status == 'accepted' ? 'Why accepted' : 'Why closed',
            r.closureNote),
      ],
      right: [
        Row(children: [
          Expanded(child: DetailField('Risk owner', r.owner)),
          Expanded(child: DetailField('Assignee', r.assignee)),
        ]),
        DetailField('Status update', r.statusNote),
        Row(children: [
          Expanded(child: DetailField('Due date', du.formatDate(r.dueDate))),
          Expanded(
              child: DetailField('Last review', du.formatDate(r.lastReviewedAt))),
          Expanded(
              child: DetailField('Next review', du.formatDate(r.nextReviewAt),
                  valueColor: overdueReview ? KColors.amber : null)),
        ]),
        Row(children: [
          Expanded(
              child: DetailField('Enterprise risk link', r.enterpriseRiskLink)),
          Expanded(
              child: DetailField(
                  'Raised on', du.formatDate(r.createdAt.toIso8601String()))),
        ]),
        Row(children: [
          Expanded(child: DetailField('Source', r.source)),
          Expanded(child: DetailField('Source Note', r.sourceNote)),
        ]),
        JournalSourceLink(
          db: widget.db,
          projectId: widget.projectId,
          itemId: r.id,
          itemText: r.title ?? r.description,
        ),
        RaidLinksSection(
          db: widget.db,
          projectId: widget.projectId,
          itemType: RaidKind.risk,
          itemId: r.id,
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

  Widget _ratingRow({
    required String likelihoodLabelText,
    required String consequenceLabelText,
    required String? likelihood,
    required String? consequence,
    required ValueChanged<String?> onLikelihood,
    required ValueChanged<String?> onConsequence,
    bool allowNone = false,
  }) {
    final lItems = [if (allowNone) '', ...kLikelihoodScale];
    final cItems = [if (allowNone) '', ...kConsequenceScale];
    return Row(children: [
      Expanded(
        child: DropdownField(
          label: likelihoodLabelText,
          value: likelihood ?? '',
          items: lItems,
          labelOverrides: {...kLikelihoodLabels, '': '— not set —'},
          onChanged: (v) => onLikelihood(v == null || v.isEmpty ? null : v),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: DropdownField(
          label: consequenceLabelText,
          value: consequence ?? '',
          items: cItems,
          labelOverrides: {...kConsequenceLabels, '': '— not set —'},
          onChanged: (v) => onConsequence(v == null || v.isEmpty ? null : v),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = _isEdit;
    final targetSet = _likelihoodTarget != null || _impactTarget != null;
    final targetEqualsCurrent = targetSet &&
        (_likelihoodTarget ?? _likelihood) == _likelihood &&
        (_impactTarget ?? _impact) == _impact;

    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.risk?.ref != null) ...[
          DetailRefChip(widget.risk!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(child: DetailTitle(isEdit ? 'Edit Risk' : 'New Risk')),
        _scoreChip(_likelihood, _impact),
        if (isEdit) ...[
          const SizedBox(width: 10),
          RaidConvertButton(
            db: widget.db,
            from: RaidKind.risk,
            itemId: widget.risk!.id,
            itemRef: widget.risk!.ref,
            sourceProjectId: widget.risk!.sourceProjectId,
          ),
        ],
      ],
      left: [
        TextFormField(
          controller: _titleCtrl,
          autofocus: !isEdit,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Risk (title)',
            hintText: 'Short, scannable headline, e.g. "AWS connections land late"',
          ),
        ),
        const SizedBox(height: 12),
        AiAssistedLabel(
          label: 'Description',
          target: _descCtrl,
          tooltip: 'Rewrite as "If [cause], then [event] may occur, '
              'resulting in [impact]" from what is here',
          buildPrompt: () => _prompt(RiskAssistField.description),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _descCtrl,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: InputDecoration(
            hintText: kRaidStatementPatterns[RaidKind.risk],
            alignLabelWithHint: true,
            isDense: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        RaidQualityHints(
          kind: RaidKind.risk,
          description: _descCtrl,
          title: _titleCtrl,
          owner: _ownerCtrl,
        ),
        const SizedBox(height: 16),
        const DetailSectionLabel('Current rating'),
        const SizedBox(height: 6),
        _ratingRow(
          likelihoodLabelText: 'Likelihood (current)',
          consequenceLabelText: 'Consequence (current)',
          likelihood: _likelihood,
          consequence: _impact,
          onLikelihood: (v) => setState(() => _likelihood = v ?? _likelihood),
          onConsequence: (v) => setState(() => _impact = v ?? _impact),
        ),
        const SizedBox(height: 12),
        AiAssistedLabel(
          label: 'Why this likelihood?',
          target: _likelihoodWhyCtrl,
          tooltip: 'Draft the likelihood rationale from the risk and '
              'project context',
          buildPrompt: () => _prompt(RiskAssistField.likelihoodRationale),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _likelihoodWhyCtrl,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Optional — the drivers and evidence behind the rating',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        AiAssistedLabel(
          label: 'Why this consequence?',
          target: _impactWhyCtrl,
          tooltip: 'Draft the consequence rationale from the risk and project '
              'context',
          buildPrompt: () => _prompt(RiskAssistField.impactRationale),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _impactWhyCtrl,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Optional — which of schedule, cost, scope, quality '
                'is hit, and how badly',
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        const DetailSectionLabel('Treatment'),
        const SizedBox(height: 6),
        DropdownField(
          label: 'Strategy',
          value: _strategy,
          items: kRiskStrategies,
          labelOverrides: kRiskStrategyLabels,
          isExpanded: true,
          onChanged: (v) => setState(() => _strategy = v ?? 'treat'),
        ),
        const SizedBox(height: 12),
        AiAssistedLabel(
          label: 'Treatment plan',
          target: _mitigationCtrl,
          tooltip: 'Draft a treatment plan from the risk and project context',
          buildPrompt: () => _prompt(RiskAssistField.mitigation),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _mitigationCtrl,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'How we reduce the likelihood, soften the consequence, '
                'and what warns us early',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _ratingRow(
          likelihoodLabelText: 'Likelihood (target)',
          consequenceLabelText: 'Consequence (target)',
          likelihood: _likelihoodTarget,
          consequence: _impactTarget,
          allowNone: true,
          onLikelihood: (v) => setState(() => _likelihoodTarget = v),
          onConsequence: (v) => setState(() => _impactTarget = v),
        ),
        if (targetSet) ...[
          const SizedBox(height: 8),
          Row(children: [
            _scoreChip(_likelihoodTarget ?? _likelihood,
                _impactTarget ?? _impact,
                prefix: 'Target: '),
            if (targetEqualsCurrent && _strategy == 'treat') ...[
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Target equals current — if the treatment changes nothing, '
                  'the strategy should be Tolerate.',
                  style: TextStyle(color: KColors.amber, fontSize: 10),
                ),
              ),
            ],
          ]),
        ],
        const SizedBox(height: 12),
      ],
      right: [
        Row(children: [
          Expanded(
            child: PersonPickerField(
              controller: _ownerCtrl,
              label: 'Risk owner (accountable)',
              persons: _persons,
              db: widget.db,
              projectId: widget.projectId,
              onPersonCreated: _loadPersons,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PersonPickerField(
              controller: _assigneeCtrl,
              label: 'Assignee (does the treatment)',
              persons: _persons,
              db: widget.db,
              projectId: widget.projectId,
              onPersonCreated: _loadPersons,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownField(
              label: 'Status',
              value: _status,
              items: _statuses,
              onChanged: (v) => setState(() => _status = v!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: _steerco,
                  onChanged: (v) => setState(() => _steerco = v ?? false),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.warning_amber_rounded,
                  size: 13, color: KColors.red),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'Escalate this risk',
                  style: TextStyle(color: KColors.text, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ]),
        if (_steerco) ...[
          const SizedBox(height: 4),
          const Text(
            'Marks the risk as raised above the project. Where you take it — '
            'sponsor, SteerCo, programme board — is your call; it leads the '
            'status report and the Top Risks list either way.',
            style: TextStyle(color: KColors.textMuted, fontSize: 10),
          ),
        ],
        if (isTerminalStatus(RaidKind.risk, _status)) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _closureNoteCtrl,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(color: KColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: _status == 'accepted' ? 'Why accepted' : 'Why closed',
              hintText: _status == 'accepted'
                  ? 'Why we live with this risk rather than act on it'
                  : 'What happened — mitigated, did not materialise, '
                      'superseded, out of scope…',
              alignLabelWithHint: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const DetailSectionLabel('Review'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: DatePickerField(
              label: 'Due date (treatment in effect)',
              isoValue: _dueDate,
              onChanged: (v) => setState(() => _dueDate = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DatePickerField(
              label: 'Last review',
              isoValue: _lastReviewedAt,
              onChanged: (v) => setState(() => _lastReviewedAt = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DatePickerField(
              label: 'Next review',
              isoValue: _nextReviewAt,
              onChanged: (v) => setState(() => _nextReviewAt = v),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          TextButton.icon(
            onPressed: _reviewedToday,
            icon: const Icon(Icons.event_available, size: 14),
            label: const Text('Reviewed today (+14 days)',
                style: TextStyle(fontSize: 11)),
          ),
          if (reviewOverdue(_nextReviewAt, DateTime.now()))
            const Text('Review overdue',
                style: TextStyle(color: KColors.amber, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          controller: _statusNoteCtrl,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Status update (notes)',
            hintText: 'One or two lines for the fortnightly report',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _enterpriseLinkCtrl.text),
          optionsBuilder: (v) => kEnterpriseRiskLinks.where((o) =>
              o.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (v) => _enterpriseLinkCtrl.text = v,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) {
            ctrl.addListener(() => _enterpriseLinkCtrl.text = ctrl.text);
            return TextFormField(
              controller: ctrl,
              focusNode: focus,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Enterprise risk link',
                hintText: 'e.g. Strategic Delivery, Process Failure',
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
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
        ]),
        if (isEdit) ...[
          const SizedBox(height: 12),
          JournalSourceLink(
            db: widget.db,
            projectId: widget.projectId,
            itemId: widget.risk!.id,
            itemText: widget.risk!.title ?? widget.risk!.description,
          ),
          const DetailDivider(),
          RaidLinksSection(
            db: widget.db,
            projectId: widget.projectId,
            itemType: RaidKind.risk,
            itemId: widget.risk!.id,
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/llm_client.dart';
import '../../core/llm/llm_client_factory.dart';
import '../../core/raid/raid_conversion_service.dart' show RaidKind, RaidKindExt;
import '../../core/raid/raid_duplicates.dart';
import '../../core/raid/raid_merge_service.dart';
import '../../core/raid/raid_statements.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'assumption_form.dart';
import 'dependency_form.dart';
import 'issue_form.dart';
import 'risk_form.dart';

/// Opens the duplicate check for [projectId] as a full screen.
Future<void> showRaidDuplicates(
  BuildContext context,
  AppDatabase db,
  String projectId,
) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RaidDuplicatesView(db: db, projectId: projectId),
      ),
    );

/// "Find duplicates" as a screen. The check runs on entry; every match
/// the model proposes sits in the left rail and the selected one fills
/// the main pane with each member laid out in full. From there the PM
/// can edit any member in its own form (reword it, fix a field the
/// model misread, convert it to another register), pick the survivor,
/// take or edit the merged wording, and either merge or mark the pair
/// as not duplicates. Nothing is written until Merge, and merging never
/// deletes: the other members close with a note naming the survivor.
class RaidDuplicatesView extends StatefulWidget {
  final AppDatabase db;
  final String projectId;

  /// Test seam: the client to ask. Built from settings when null.
  final LLMClient? client;

  const RaidDuplicatesView({
    super.key,
    required this.db,
    required this.projectId,
    this.client,
  });

  @override
  State<RaidDuplicatesView> createState() => _RaidDuplicatesViewState();
}

enum _Phase { checking, ready, failed }

/// What the PM decided about a match. [resolved] is not a decision: the
/// register changed under the match (a member was closed or merged from
/// a form) and fewer than two members are left to compare.
enum _Verdict { open, merged, kept, resolved }

/// The PM's working choices for one match, kept while they move between
/// matches so nothing typed is lost.
class _Draft {
  String? survivorId;
  RaidKind? keepAs;
  bool useMerged;
  String mergedText;
  _Draft({
    required this.survivorId,
    required this.keepAs,
    required this.useMerged,
    required this.mergedText,
  });
}

class _RaidDuplicatesViewState extends State<RaidDuplicatesView> {
  _Phase _phase = _Phase.checking;
  int _openCount = 0;
  List<DuplicateItem> _items = const [];
  List<DuplicateGroup> _groups = const [];
  final _verdicts = <int, _Verdict>{};
  final _notes = <int, String>{};

  /// What the rail calls each match. Frozen once a match is decided, so
  /// a merged pair still reads "A1 + D1" after the refresh shrinks the
  /// group to its survivor.
  final _railLabels = <int, String>{};
  final _drafts = <int, _Draft>{};
  String _error = '';
  bool _cancelled = false;

  int? _selected;
  final _mergedCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mergedCtrl.addListener(() {
      final d = _draft;
      if (d != null) d.mergedText = _mergedCtrl.text;
    });
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    _mergedCtrl.dispose();
    super.dispose();
  }

  // ── Data ─────────────────────────────────────────────────────────────

  Future<List<DuplicateItem>> _collect() async {
    final dao = widget.db.raidDao;
    final pid = widget.projectId;
    return collectDuplicateItems(
      risks: await dao.getRisksForProject(pid),
      assumptions: await dao.getAssumptionsForProject(pid),
      issues: await dao.getIssuesForProject(pid),
      dependencies: await dao.getDependenciesForProject(pid),
    );
  }

  Future<void> _start() async {
    // Read providers before the first await — the screen may be popped
    // while the register loads.
    final client = widget.client ??
        LLMClientFactory.fromSettings(context.read<SettingsProvider>().settings);
    setState(() {
      _phase = _Phase.checking;
      _groups = const [];
      _verdicts.clear();
      _notes.clear();
      _railLabels.clear();
      _drafts.clear();
      _selected = null;
    });
    try {
      _items = await _collect();
      _openCount = _items.length;
      if (_cancelled || !mounted) return;
      if (_items.length < 2) {
        setState(() => _phase = _Phase.ready);
        return;
      }
      final ctx = await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
      if (_cancelled || !mounted) return;
      final p = duplicatesPrompt(_items, projectContext: ctx);
      final raw = await client.complete(
        systemPrompt: p.system,
        userMessage: p.user,
        maxTokens: 1500,
      );
      if (_cancelled || !mounted) return;
      _groups = parseDuplicateGroups(raw, _items);
      for (var i = 0; i < _groups.length; i++) {
        _verdicts[i] = _Verdict.open;
        _railLabels[i] = _railLabel(_groups[i]);
      }
      setState(() {
        _phase = _Phase.ready;
        if (_groups.isNotEmpty) _select(0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _phase = _Phase.failed;
      });
    }
  }

  /// Re-reads the register and rebuilds every match from what is open
  /// now, so a member edited, converted or closed in its form is seen as
  /// it is — the merge closes by kind and id, and a stale kind would
  /// miss. Matches left with fewer than two members become resolved.
  Future<void> _refresh() async {
    _items = await _collect();
    if (!mounted) return;
    _openCount = _items.length;
    _groups = refreshGroups(_groups, _items);
    for (var i = 0; i < _groups.length; i++) {
      if (_verdicts[i] == _Verdict.open) {
        _railLabels[i] = _railLabel(_groups[i]);
      }
      if (_verdicts[i] == _Verdict.open && _groups[i].members.length < 2) {
        _verdicts[i] = _Verdict.resolved;
        _notes[i] = _groups[i].members.isEmpty
            ? 'None of these is still open, so there is nothing left to merge.'
            : 'Only one of these is still open, so there is nothing left to merge.';
      }
      final d = _drafts[i];
      if (d != null) _validateDraft(d, _groups[i]);
    }
    setState(() {});
  }

  String _railLabel(DuplicateGroup g) => g.members.map((m) => m.label).join('  +  ');

  // ── Selection and drafts ─────────────────────────────────────────────

  _Draft? get _draft => _selected == null ? null : _drafts[_selected!];

  _Draft _newDraft(DuplicateGroup g) {
    // Default survivor: the member already in the suggested register,
    // else the first.
    final inRegister = g.members.where((m) => m.kind == g.register).firstOrNull;
    return _Draft(
      survivorId: (inRegister ?? g.members.firstOrNull)?.id,
      keepAs: g.register,
      useMerged: g.merged.isNotEmpty,
      mergedText: g.merged,
    );
  }

  /// Keeps a draft's choices legal against the match as it is now.
  void _validateDraft(_Draft d, DuplicateGroup g) {
    if (g.members.isEmpty) return;
    if (!g.members.any((m) => m.id == d.survivorId)) {
      d.survivorId = _newDraft(g).survivorId;
    }
    if (!g.members.any((m) => m.kind == d.keepAs)) {
      d.keepAs = g.members.firstWhere((m) => m.id == d.survivorId).kind;
    }
  }

  void _select(int i) {
    _selected = i;
    final d = _drafts.putIfAbsent(i, () => _newDraft(_groups[i]));
    _validateDraft(d, _groups[i]);
    // Setting the controller text fires the listener, which writes the
    // same text back to the same draft.
    _mergedCtrl.text = d.mergedText;
  }

  DuplicateItem? get _survivor {
    final d = _draft;
    if (d == null || _selected == null) return null;
    return _groups[_selected!].members.where((m) => m.id == d.survivorId).firstOrNull;
  }

  // ── Decisions ────────────────────────────────────────────────────────

  void _keepSeparate() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      _verdicts[i] = _Verdict.kept;
      _notes[i] = 'Kept separate — nothing was changed.';
    });
  }

  void _reopen() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      _verdicts[i] = _Verdict.open;
      _notes.remove(i);
    });
  }

  Future<void> _merge() async {
    final i = _selected;
    final d = _draft;
    final survivor = _survivor;
    if (_busy || i == null || d == null || survivor == null) return;
    final g = _groups[i];
    final keepAs = d.keepAs ?? survivor.kind;
    setState(() => _busy = true);
    try {
      final outcome = await RaidMergeService(widget.db).merge(
        group: g,
        survivor: survivor,
        keepAs: keepAs,
        mergedDescription: d.useMerged ? d.mergedText : null,
      );
      if (!mounted) return;
      await _pushCascade(outcome);
      if (!mounted) return;
      final ref = outcome.survivorRef;
      final label = ref == null || ref.isEmpty
          ? outcome.survivorKind.label
          : '${outcome.survivorKind.label} $ref';
      final closed = [
        for (final m in g.members)
          if (m.id != survivor.id) m.label,
      ];
      _verdicts[i] = _Verdict.merged;
      _notes[i] = 'Merged into $label. Closed: ${closed.join(', ')}.';
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Merge failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Linked projects see the survivor's new wording and the closures.
  Future<void> _pushCascade(MergeOutcome o) async {
    final cascade = buildCascadeService(context);
    final dao = widget.db.raidDao;
    Future<void> push(RaidKind kind, String id) async {
      switch (kind) {
        case RaidKind.risk:
          final x = await dao.getRiskById(id);
          if (x != null) await cascade.pushRisk(x);
        case RaidKind.assumption:
          final x = await dao.getAssumptionById(id);
          if (x != null) await cascade.pushAssumption(x);
        case RaidKind.issue:
          final x = await dao.getIssueById(id);
          if (x != null) await cascade.pushIssue(x);
        case RaidKind.dependency:
          final x = await dao.getDependencyById(id);
          if (x != null) await cascade.pushDependency(x);
        case RaidKind.decision:
          break;
      }
    }

    await push(o.survivorKind, o.survivorId);
    for (final (kind, id) in o.closed) {
      await push(kind, id);
    }
  }

  /// Opens the member's own form in edit mode, then re-reads the
  /// register: the PM may have reworded it, changed a field, converted
  /// it to another register or closed it.
  Future<void> _edit(DuplicateItem m) async {
    final dao = widget.db.raidDao;
    final pid = widget.projectId;
    Widget? form;
    switch (m.kind) {
      case RaidKind.risk:
        final r = await dao.getRiskById(m.id);
        if (r != null) form = RiskFormDialog(projectId: pid, db: widget.db, risk: r);
      case RaidKind.assumption:
        final a = await dao.getAssumptionById(m.id);
        if (a != null) {
          form = AssumptionFormDialog(projectId: pid, db: widget.db, assumption: a);
        }
      case RaidKind.issue:
        final x = await dao.getIssueById(m.id);
        if (x != null) form = IssueFormDialog(projectId: pid, db: widget.db, issue: x);
      case RaidKind.dependency:
        final x = await dao.getDependencyById(m.id);
        if (x != null) {
          form = DependencyFormDialog(projectId: pid, db: widget.db, dependency: x);
        }
      case RaidKind.decision:
        break;
    }
    if (!mounted) return;
    if (form != null) {
      final f = form;
      await showDialog(context: context, builder: (_) => f);
    }
    if (mounted) await _refresh();
  }

  // ── Build ────────────────────────────────────────────────────────────

  int _count(_Verdict v) => _verdicts.values.where((x) => x == v).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.bg,
      appBar: AppBar(
        backgroundColor: KColors.surface,
        foregroundColor: KColors.text,
        title: Row(
          children: [
            Icon(Icons.call_merge, color: KColors.amber, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'FIND DUPLICATES',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KColors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_phase != _Phase.checking)
            TextButton.icon(
              onPressed: _busy ? null : _start,
              icon: Icon(Icons.refresh, size: 14, color: KColors.textDim),
              label: Text(
                'Check again',
                style: TextStyle(color: KColors.textDim, fontSize: 12),
              ),
            ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Done', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 16),
        ],
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KColors.border),
        ),
      ),
      body: switch (_phase) {
        _Phase.checking => _checking(),
        _Phase.failed => _failed(),
        _Phase.ready => _groups.isEmpty ? _nothingFound() : _ready(),
      },
    );
  }

  Widget _checking() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              color: KColors.phosphor,
              backgroundColor: KColors.surface2,
            ),
            const SizedBox(height: 14),
            Text(
              _openCount == 0
                  ? 'Reading the register…'
                  : 'Comparing $_openCount open items…',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'Closed items and copies from linked projects are never touched.',
              style: TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The check could not be completed.',
              style: TextStyle(color: KColors.text, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SelectableText(
              _error,
              style: TextStyle(color: KColors.amber, fontSize: 11.5),
            ),
            const SizedBox(height: 6),
            Text(
              'Nothing was changed. Check the AI settings and try again.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nothingFound() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _openCount < 2
                  ? 'Nothing to compare yet.'
                  : 'No duplicates found among $_openCount open items.',
              style: TextStyle(color: KColors.text, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              _openCount < 2
                  ? 'The check needs at least two open items in the register.'
                  : 'The model saw nothing that says the same thing twice. '
                      'Items that merely share a topic are left alone on purpose.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ready() {
    return Column(
      children: [
        _summaryStrip(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 300,
                decoration: BoxDecoration(
                  color: KColors.surface,
                  border: Border(right: BorderSide(color: KColors.border)),
                ),
                child: _rail(),
              ),
              Expanded(child: _detail()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryStrip() {
    final open = _count(_Verdict.open);
    final merged = _count(_Verdict.merged);
    final kept = _count(_Verdict.kept);
    final resolved = _count(_Verdict.resolved);
    Widget stat(String label, int n, Color color) => Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$n ',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: label,
                  style: TextStyle(color: KColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          stat('matches among $_openCount open items', _groups.length, KColors.text),
          stat('to decide', open, KColors.amber),
          stat('merged', merged, KColors.phosphor),
          stat('kept separate', kept, KColors.textDim),
          if (resolved > 0) stat('resolved elsewhere', resolved, KColors.textDim),
        ],
      ),
    );
  }

  Widget _rail() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _groups.length,
      itemBuilder: (_, i) {
        final g = _groups[i];
        final v = _verdicts[i] ?? _Verdict.open;
        final sel = i == _selected;
        final (chip, color) = switch (v) {
          _Verdict.open => ('TO DECIDE', KColors.amber),
          _Verdict.merged => ('MERGED', KColors.phosphor),
          _Verdict.kept => ('KEPT', KColors.textMuted),
          _Verdict.resolved => ('RESOLVED', KColors.textMuted),
        };
        final dim = v != _Verdict.open;
        return InkWell(
          onTap: () => setState(() => _select(i)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: sel ? KColors.surface2 : null,
              border: Border(
                left: BorderSide(
                  color: sel ? KColors.amber : Colors.transparent,
                  width: 2,
                ),
                bottom: BorderSide(color: KColors.border.withValues(alpha: 0.6)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _railLabels[i] ?? _railLabel(g),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: dim ? KColors.textDim : KColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _tag(chip, color),
                  ],
                ),
                if (g.reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    g.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detail() {
    final i = _selected;
    if (i == null) {
      return Center(
        child: Text(
          'Pick a match on the left.',
          style: TextStyle(color: KColors.textMuted, fontSize: 12),
        ),
      );
    }
    final g = _groups[i];
    final v = _verdicts[i] ?? _Verdict.open;
    final d = _draft!;
    final decided = v != _Verdict.open;
    final keepAs = d.keepAs ?? g.register;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MATCH ${i + 1} OF ${_groups.length}',
            style: TextStyle(
              color: KColors.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (g.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              g.reason,
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
          if (decided) ...[
            const SizedBox(height: 12),
            _decisionBanner(v, _notes[i] ?? ''),
          ],
          const SizedBox(height: 14),
          for (final m in g.members) ...[
            _memberCard(m, d, decided: decided),
            const SizedBox(height: 10),
          ],
          if (!decided) ...[
            if (g.crossesRegisters) ...[
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  Text(
                    'Keep the survivor as',
                    style: TextStyle(color: KColors.textMuted, fontSize: 11),
                  ),
                  SegmentedButton<RaidKind>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      for (final k in g.kinds)
                        ButtonSegment(
                          value: k,
                          label: Text(k.label, style: const TextStyle(fontSize: 11)),
                        ),
                    ],
                    selected: {keepAs},
                    onSelectionChanged: (s) => setState(() => d.keepAs = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _pane(
              label: 'MERGED WORDING  ·  edit before merging if you like',
              accent: KColors.phosphor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _mergedCtrl,
                    minLines: 2,
                    maxLines: 8,
                    enabled: d.useMerged,
                    style: TextStyle(
                      color: d.useMerged ? KColors.text : KColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText:
                          'No merged statement offered — the survivor keeps its wording.',
                    ),
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: d.useMerged,
                        visualDensity: VisualDensity.compact,
                        onChanged: (x) => setState(() => d.useMerged = x ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Use this wording on the survivor (its current wording is kept in the source note)',
                          style: TextStyle(color: KColors.textDim, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  if (kRaidStatementPatterns[keepAs] != null)
                    Text(
                      'Aim for: ${kRaidStatementPatterns[keepAs]}',
                      style: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _busy ? null : _keepSeparate,
                  child: const Text('Not duplicates'),
                ),
                ElevatedButton.icon(
                  onPressed: _busy || _survivor == null ? null : _merge,
                  icon: const Icon(Icons.call_merge, size: 14),
                  label: Text(_mergeLabel(d)),
                ),
                Text(
                  'Or leave it and come back: your choices here are kept while you look at other matches.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ] else if (v == _Verdict.kept)
            TextButton(
              onPressed: _reopen,
              child: const Text('Reconsider'),
            ),
        ],
      ),
    );
  }

  String _mergeLabel(_Draft d) {
    final s = _survivor;
    if (s == null) return 'Merge';
    final into = d.keepAs != null && d.keepAs != s.kind
        ? '${s.label} as ${d.keepAs!.label.toLowerCase()}'
        : s.label;
    return 'Merge into $into';
  }

  Widget _decisionBanner(_Verdict v, String note) {
    final color = switch (v) {
      _Verdict.merged => KColors.phosphor,
      _ => KColors.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            v == _Verdict.merged ? Icons.check_circle_outline : Icons.info_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// One member, full width: statement in full, every field in full.
  Widget _memberCard(DuplicateItem m, _Draft d, {required bool decided}) {
    final selected = !decided && m.id == d.survivorId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(
          color: selected ? KColors.phosphor : KColors.border2.withValues(alpha: 0.7),
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!decided)
                InkWell(
                  onTap: () => setState(() {
                    d.survivorId = m.id;
                    // Picking a survivor in another register moves the
                    // default register with it; the segmented control can
                    // still override.
                    d.keepAs = m.kind;
                  }),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 14,
                          color: selected ? KColors.phosphor : KColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          selected ? 'SURVIVOR' : 'KEEP THIS ONE',
                          style: TextStyle(
                            color: selected ? KColors.phosphor : KColors.textMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!decided) const SizedBox(width: 12),
              _tag(m.kind.label.toUpperCase(), KColors.textMuted),
              if (m.ref != null && m.ref!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  m.ref!,
                  style: TextStyle(
                    color: KColors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: _busy ? null : () => _edit(m),
                icon: Icon(Icons.edit_outlined, size: 13, color: KColors.textDim),
                label: Text(
                  'Edit',
                  style: TextStyle(color: KColors.textDim, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (m.title != null && m.title!.trim().isNotEmpty) ...[
            SelectableText(
              m.title!.trim(),
              style: TextStyle(
                color: KColors.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
          ],
          SelectableText(
            m.description,
            style: TextStyle(color: KColors.text, fontSize: 13, height: 1.45),
          ),
          if (m.context.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final (k, v) in m.context)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        k,
                        style: TextStyle(color: KColors.textMuted, fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        v,
                        style: TextStyle(
                          color: KColors.textDim,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pane({required String label, required Widget child, Color? accent}) {
    accent ??= KColors.border2;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: accent.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent == KColors.border2 ? KColors.textMuted : accent,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}

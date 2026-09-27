import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/llm/context_builder.dart';
import '../../core/llm/llm_client_factory.dart';
import '../../core/raid/raid_conversion_service.dart' show RaidKind;
import '../../core/raid/raid_statements.dart';
import '../../core/raid/raid_tidy.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';

/// "Tidy my register": drafts a stronger statement for each weak RAID
/// item and walks the PM through them one card at a time — current on
/// the left, draft on the right, the item's other fields underneath, so
/// nothing has to be opened to judge it. Accept writes the description
/// (and keeps the old wording in the source note); Skip leaves it alone.
/// Stopping halfway keeps what was accepted.
class RaidTidyDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  const RaidTidyDialog({super.key, required this.db, required this.projectId});

  @override
  State<RaidTidyDialog> createState() => _RaidTidyDialogState();
}

enum _Phase { scope, drafting, review, done }

class _RaidTidyDialogState extends State<RaidTidyDialog> {
  _Phase _phase = _Phase.scope;
  TidyScope _scope = TidyScope.needsWork;
  int _needsWork = 0, _allOpen = 0;

  List<TidyCandidate> _queue = const [];
  final Map<String, String> _drafts = {}; // candidate id → draft
  final Map<String, String> _errors = {};
  int _drafted = 0;
  bool _cancelled = false;

  int _index = 0;
  final _editCtrl = TextEditingController();
  int _accepted = 0, _skipped = 0;

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void dispose() {
    _cancelled = true;
    _editCtrl.dispose();
    super.dispose();
  }

  Future<List<TidyCandidate>> _collect(TidyScope scope) async {
    final dao = widget.db.raidDao;
    final pid = widget.projectId;
    return collectTidyCandidates(
      risks: await dao.getRisksForProject(pid),
      assumptions: await dao.getAssumptionsForProject(pid),
      issues: await dao.getIssuesForProject(pid),
      dependencies: await dao.getDependenciesForProject(pid),
      scope: scope,
    );
  }

  Future<void> _count() async {
    final all = await _collect(TidyScope.allOpen);
    if (!mounted) return;
    setState(() {
      _allOpen = all.length;
      _needsWork = all.where((c) => c.needsWork).length;
    });
  }

  Future<void> _start() async {
    // Read providers before the first await — the dialog may be closed
    // while the register loads.
    final settings = context.read<SettingsProvider>().settings;
    final client = LLMClientFactory.fromSettings(settings);
    _queue = await _collect(_scope);
    if (!mounted) return;
    setState(() => _phase = _Phase.drafting);
    final ctx = await ContextBuilder(widget.db).buildSystemPrompt(widget.projectId);
    for (final c in _queue) {
      if (_cancelled || !mounted) return;
      try {
        final p = c.prompt(ctx);
        final draft = (await client.complete(
          systemPrompt: p.system,
          userMessage: p.user,
          maxTokens: 400,
        ))
            .trim();
        if (draft.isEmpty) {
          _errors[c.id] = 'Empty draft';
        } else {
          _drafts[c.id] = draft;
        }
      } catch (e) {
        _errors[c.id] = '$e';
      }
      if (!mounted) return;
      setState(() => _drafted++);
    }
    if (!mounted) return;
    _queue = _queue.where((c) => _drafts.containsKey(c.id)).toList();
    _index = 0;
    _loadCard();
    setState(() => _phase = _queue.isEmpty ? _Phase.done : _Phase.review);
    if (_queue.isEmpty) _count();
  }

  void _loadCard() {
    if (_index < _queue.length) {
      _editCtrl.text = _drafts[_queue[_index].id] ?? '';
    }
  }

  void _advance() {
    _index++;
    if (_index >= _queue.length) {
      setState(() => _phase = _Phase.done);
      _count(); // fresh flagged count for the summary
    } else {
      _loadCard();
      setState(() {});
    }
  }

  Future<void> _accept() async {
    final c = _queue[_index];
    final text = _editCtrl.text.trim();
    if (text.isEmpty || text == c.description.trim()) {
      _skipped++;
      _advance();
      return;
    }
    final dao = widget.db.raidDao;
    final pid = widget.projectId;
    final now = DateTime.now();
    switch (c.kind) {
      case RaidKind.risk:
        final r = await dao.getRiskById(c.id);
        if (r == null) break;
        await dao.upsertRisk(RisksCompanion(
          id: Value(r.id),
          projectId: Value(pid),
          description: Value(text),
          sourceNote: Value(tidyHistoryNote(
              existingSourceNote: r.sourceNote,
              previousDescription: r.description,
              when: now)),
          updatedAt: Value(now),
        ));
        final fresh = await dao.getRiskById(c.id);
        if (fresh != null && mounted) {
          await buildCascadeService(context).pushRisk(fresh);
        }
      case RaidKind.assumption:
        final a = await dao.getAssumptionById(c.id);
        if (a == null) break;
        await dao.upsertAssumption(AssumptionsCompanion(
          id: Value(a.id),
          projectId: Value(pid),
          description: Value(text),
          sourceNote: Value(tidyHistoryNote(
              existingSourceNote: a.sourceNote,
              previousDescription: a.description,
              when: now)),
          updatedAt: Value(now),
        ));
        final fresh = await dao.getAssumptionById(c.id);
        if (fresh != null && mounted) {
          await buildCascadeService(context).pushAssumption(fresh);
        }
      case RaidKind.issue:
        final i = await dao.getIssueById(c.id);
        if (i == null) break;
        await dao.upsertIssue(IssuesCompanion(
          id: Value(i.id),
          projectId: Value(pid),
          description: Value(text),
          sourceNote: Value(tidyHistoryNote(
              existingSourceNote: i.sourceNote,
              previousDescription: i.description,
              when: now)),
          updatedAt: Value(now),
        ));
        final fresh = await dao.getIssueById(c.id);
        if (fresh != null && mounted) {
          await buildCascadeService(context).pushIssue(fresh);
        }
      case RaidKind.dependency:
        final d = await dao.getDependencyById(c.id);
        if (d == null) break;
        await dao.upsertDependency(ProgramDependenciesCompanion(
          id: Value(d.id),
          projectId: Value(pid),
          description: Value(text),
          sourceNote: Value(tidyHistoryNote(
              existingSourceNote: d.sourceNote,
              previousDescription: d.description,
              when: now)),
          updatedAt: Value(now),
        ));
        final fresh = await dao.getDependencyById(c.id);
        if (fresh != null && mounted) {
          await buildCascadeService(context).pushDependency(fresh);
        }
      case RaidKind.decision:
        throw UnsupportedError('Decisions are not part of the tidy queue');
    }
    _accepted++;
    if (mounted) _advance();
  }

  void _skip() {
    _skipped++;
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(children: [
        const Icon(Icons.auto_fix_high, size: 16, color: KColors.phosphor),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Tidy my register',
              style: TextStyle(color: KColors.text, fontSize: 14)),
        ),
        if (_phase == _Phase.review)
          Text('${_index + 1} of ${_queue.length}',
              style: const TextStyle(color: KColors.textMuted, fontSize: 11)),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: KColors.textMuted),
          tooltip: _phase == _Phase.review
              ? 'Stop — what you accepted stays'
              : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      content: SizedBox(
        width: 820,
        child: switch (_phase) {
          _Phase.scope => _scopeStep(),
          _Phase.drafting => _draftingStep(),
          _Phase.review => _reviewStep(),
          _Phase.done => _doneStep(),
        },
      ),
      actions: switch (_phase) {
        _Phase.scope => [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: (_scope == TidyScope.needsWork ? _needsWork : _allOpen) == 0
                  ? null
                  : _start,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('Draft them'),
            ),
          ],
        _Phase.drafting => [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel')),
          ],
        _Phase.review => [
            TextButton(onPressed: _skip, child: const Text('Skip')),
            ElevatedButton.icon(
              onPressed: _accept,
              icon: const Icon(Icons.check, size: 14),
              label: const Text('Accept'),
            ),
          ],
        _Phase.done => [
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done')),
          ],
      },
    );
  }

  // ── Steps ────────────────────────────────────────────────────────────

  Widget _scopeStep() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'Keel drafts a stronger statement for each item, in the house '
        'shape, from what the item already says. You review them one at a '
        'time — current on the left, draft on the right — and nothing is '
        'written until you accept it. The previous wording is kept in the '
        'item\'s source note.',
        style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 14),
      RadioGroup<TidyScope>(
        groupValue: _scope,
        onChanged: (v) => setState(() => _scope = v ?? _scope),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile<TidyScope>(
            dense: true,
            value: TidyScope.needsWork,
            title: Text('Items flagged IMPROVE  ·  $_needsWork',
                style: const TextStyle(color: KColors.text, fontSize: 13)),
            subtitle: const Text('Statements missing a cause, event, impact, '
                'validation or counterparty.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11)),
          ),
          RadioListTile<TidyScope>(
            dense: true,
            value: TidyScope.allOpen,
            title: Text('Every open item  ·  $_allOpen',
                style: const TextStyle(color: KColors.text, fontSize: 13)),
            subtitle: const Text('Closed items and copies from linked projects '
                'are never touched.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11)),
          ),
        ]),
      ),
    ]);
  }

  Widget _draftingStep() {
    final total = _queue.length;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: total == 0 ? 0 : _drafted / total,
        color: KColors.phosphor,
        backgroundColor: KColors.surface2,
      ),
      const SizedBox(height: 12),
      Text('Drafting $_drafted of $total…',
          style: const TextStyle(color: KColors.textDim, fontSize: 12)),
      if (_errors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${_errors.length} could not be drafted and will be skipped.',
              style: const TextStyle(color: KColors.amber, fontSize: 11)),
        ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _reviewStep() {
    final c = _queue[_index];
    final kindLabel = kindLabelFor(c.kind).toUpperCase();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _tag(kindLabel, KColors.textMuted),
            if (c.ref != null) ...[
              const SizedBox(width: 8),
              Text(c.ref!,
                  style: const TextStyle(
                      color: KColors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
            if (c.title != null && c.title!.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(c.title!,
                    style: const TextStyle(
                        color: KColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ] else
              const Spacer(),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _pane(
                label: 'CURRENT',
                child: SelectableText(c.description,
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 13, height: 1.4)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _pane(
                label: 'DRAFT  ·  edit before accepting if you like',
                accent: KColors.phosphor,
                child: TextField(
                  controller: _editCtrl,
                  minLines: 3,
                  maxLines: 8,
                  style: const TextStyle(color: KColors.text, fontSize: 13, height: 1.4),
                  decoration: const InputDecoration(
                      isDense: true, border: InputBorder.none),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text('Aim for: ${kRaidStatementPatterns[c.kind]}',
              style: const TextStyle(
                  color: KColors.textMuted, fontSize: 10.5, fontStyle: FontStyle.italic)),
          if (c.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('WHY IT WAS FLAGGED',
                style: TextStyle(
                    color: KColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            for (final h in c.hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• ${h.text}',
                    style: TextStyle(
                        color: h.severity == 2 ? KColors.amber : KColors.textDim,
                        fontSize: 11)),
              ),
          ],
          if (c.context.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('THE REST OF THE ITEM',
                style: TextStyle(
                    color: KColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Wrap(spacing: 16, runSpacing: 4, children: [
              for (final (k, v) in c.context)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$k  ',
                        style: const TextStyle(color: KColors.textMuted, fontSize: 11)),
                    TextSpan(
                        text: v,
                        style: const TextStyle(color: KColors.textDim, fontSize: 11)),
                  ]), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _doneStep() {
    // _needsWork is re-counted on entering this step (see _advance).
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Accepted $_accepted · skipped $_skipped'
          '${_errors.isNotEmpty ? ' · ${_errors.length} could not be drafted' : ''}',
          style: const TextStyle(color: KColors.text, fontSize: 13)),
      const SizedBox(height: 6),
      Text(
        _needsWork == 0
            ? 'Nothing left flagged IMPROVE.'
            : '$_needsWork still flagged — run again or fix in the forms.',
        style: const TextStyle(color: KColors.textDim, fontSize: 12),
      ),
    ]);
  }

  Widget _pane({required String label, required Widget child, Color accent = KColors.border2}) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: accent.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: accent == KColors.border2 ? KColors.textMuted : accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          child,
        ]),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );
}

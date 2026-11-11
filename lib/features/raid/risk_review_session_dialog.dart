import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/raid/raid_conversion_service.dart' show RaidKind, RaidKindExt;
import '../../core/raid/raid_lifecycle.dart';
import '../../core/raid/risk_rating.dart';
import '../../core/raid/risk_review.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/dropdown_field.dart';

/// Opens the review session for one project. Helm's "review session"
/// row and the RAID log's button both land here.
Future<void> showRiskReviewSession(
  BuildContext context,
  AppDatabase db,
  String projectId, {
  ReviewScope scope = ReviewScope.overdue,
}) =>
    showDialog(
      context: context,
      builder: (_) => RiskReviewSessionDialog(
        db: db,
        projectId: projectId,
        initialScope: scope,
      ),
    );

/// "Review risks": walks the PM through the risks due a look, one card
/// at a time. Each card shows the statement with its rating, treatment,
/// status and a note field for what changed; Reviewed saves the edits
/// and stamps the review dates (today, and a fortnight out), Skip leaves
/// the risk exactly as it was. Stopping halfway keeps what was reviewed.
class RiskReviewSessionDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final ReviewScope initialScope;

  /// Test seam for "today".
  final DateTime? today;

  const RiskReviewSessionDialog({
    super.key,
    required this.db,
    required this.projectId,
    this.initialScope = ReviewScope.overdue,
    this.today,
  });

  @override
  State<RiskReviewSessionDialog> createState() => _RiskReviewSessionDialogState();
}

enum _Phase { scope, review, done }

class _RiskReviewSessionDialogState extends State<RiskReviewSessionDialog> {
  _Phase _phase = _Phase.scope;
  late ReviewScope _scope = widget.initialScope;
  int _overdue = 0, _allOpen = 0;

  List<Risk> _queue = const [];
  int _index = 0;
  int _reviewed = 0, _skipped = 0;
  bool _busy = false;

  // The card's editable state.
  String _likelihood = 'possible';
  String _impact = 'moderate';
  String _status = 'open';
  final _mitigationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _count();
  }

  @override
  void dispose() {
    _mitigationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<List<Risk>> _collect(ReviewScope scope) async => collectReviewCandidates(
        risks: await widget.db.raidDao.getRisksForProject(widget.projectId),
        today: _today,
        scope: scope,
      );

  Future<void> _count() async {
    final all = await _collect(ReviewScope.allOpen);
    final overdue = await _collect(ReviewScope.overdue);
    if (!mounted) return;
    setState(() {
      _allOpen = all.length;
      _overdue = overdue.length;
    });
  }

  Future<void> _start() async {
    _queue = await _collect(_scope);
    if (!mounted) return;
    _index = 0;
    _loadCard();
    setState(() => _phase = _queue.isEmpty ? _Phase.done : _Phase.review);
  }

  void _loadCard() {
    if (_index >= _queue.length) return;
    final r = _queue[_index];
    _likelihood = normaliseLikelihood(r.likelihood);
    _impact = normaliseConsequence(r.impact);
    _status = r.status;
    _mitigationCtrl.text = r.mitigation ?? '';
    _noteCtrl.text = '';
  }

  void _advance() {
    _index++;
    if (_index >= _queue.length) {
      setState(() => _phase = _Phase.done);
    } else {
      _loadCard();
      setState(() {});
    }
  }

  void _skip() {
    _skipped++;
    _advance();
  }

  Future<void> _markReviewed() async {
    if (_busy) return;
    final r = _queue[_index];
    setState(() => _busy = true);
    try {
      final stamp = reviewStamp(_today);
      final note = _noteCtrl.text.trim();
      final mitigation = _mitigationCtrl.text.trim();
      await widget.db.raidDao.upsertRisk(RisksCompanion(
        id: Value(r.id),
        projectId: Value(r.projectId),
        // The DAO's upsert is insert-or-update; the insert shape needs it.
        description: Value(r.description),
        likelihood: Value(_likelihood),
        impact: Value(_impact),
        mitigation: Value(mitigation.isEmpty ? null : mitigation),
        status: Value(_status),
        closedAt: Value(nextClosedAt(
          kind: RaidKind.risk,
          newStatus: _status,
          existing: r.closedAt,
          today: _today,
        )),
        // A fresh note replaces the old one; the old one is this review's
        // starting point, not history worth keeping twice.
        statusNote: Value(note.isEmpty ? r.statusNote : note),
        lastReviewedAt: Value(stamp.last),
        nextReviewAt: Value(stamp.next),
        updatedAt: Value(DateTime.now()),
      ));
      if (!mounted) return;
      final fresh = await widget.db.raidDao.getRiskById(r.id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushRisk(fresh);
      }
      _reviewed++;
      if (mounted) _advance();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          Icon(Icons.fact_check_outlined, size: 16, color: KColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Review risks',
              style: TextStyle(color: KColors.text, fontSize: 14),
            ),
          ),
          if (_phase == _Phase.review)
            Text(
              '${_index + 1} of ${_queue.length}',
              style: TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: KColors.textMuted),
            tooltip: _phase == _Phase.review
                ? 'Stop — what you reviewed stays'
                : 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: switch (_phase) {
          _Phase.scope => _scopeStep(),
          _Phase.review => _reviewStep(),
          _Phase.done => _doneStep(),
        },
      ),
      actions: switch (_phase) {
        _Phase.scope => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed:
                (_scope == ReviewScope.overdue ? _overdue : _allOpen) == 0
                    ? null
                    : _start,
            icon: const Icon(Icons.play_arrow, size: 14),
            label: const Text('Start the session'),
          ),
        ],
        _Phase.review => [
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('Skip'),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _markReviewed,
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Reviewed'),
          ),
        ],
        _Phase.done => [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      },
    );
  }

  // ── Steps ────────────────────────────────────────────────────────────

  Widget _scopeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'One risk at a time: re-rate it, adjust the treatment, note what '
          'changed, and mark it reviewed. Each review stamps today and sets '
          'the next one $kRiskReviewCadenceDays days out, so Helm stops '
          'offering it until then. Skip leaves a risk exactly as it was.',
          style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),
        RadioGroup<ReviewScope>(
          groupValue: _scope,
          onChanged: (v) => setState(() => _scope = v ?? _scope),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ReviewScope>(
                dense: true,
                value: ReviewScope.overdue,
                title: Text(
                  'Reviews overdue  ·  $_overdue',
                  style: TextStyle(color: KColors.text, fontSize: 13),
                ),
                subtitle: Text(
                  'Longest-neglected first.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 11),
                ),
              ),
              RadioListTile<ReviewScope>(
                dense: true,
                value: ReviewScope.allOpen,
                title: Text(
                  'Every open risk  ·  $_allOpen',
                  style: TextStyle(color: KColors.text, fontSize: 13),
                ),
                subtitle: Text(
                  'Overdue first, then by rating. Closed and accepted risks, '
                  'and copies from linked projects, are not reviewed here.',
                  style: TextStyle(color: KColors.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    final r = _queue[_index];
    final band = riskBand(_likelihood, _impact);
    final bandColor = switch (band) {
      'high' => KColors.red,
      'medium' => KColors.amber,
      _ => KColors.phosphor,
    };
    final overdue = reviewOverdue(r.nextReviewAt, _today);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 560),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (r.ref != null)
                  Text(
                    r.ref!,
                    style: TextStyle(
                      color: KColors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.title?.trim().isNotEmpty == true ? r.title!.trim() : r.description,
                    style: TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                _tag(ratingSummary(_likelihood, _impact).toUpperCase(), bandColor),
              ],
            ),
            if (r.title?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              SelectableText(
                r.description,
                style: TextStyle(color: KColors.textDim, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 3,
              children: [
                _fact('Owner', r.owner),
                _fact('Treatment due', du.formatDate(r.dueDate)),
                _fact('Last reviewed', du.formatDate(r.lastReviewedAt)),
                _fact(
                  'Review was due',
                  r.nextReviewAt == null ? null : du.formatDate(r.nextReviewAt),
                  warn: overdue,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownField(
                    label: 'Likelihood',
                    value: _likelihood,
                    items: kLikelihoodScale,
                    labelOverrides: kLikelihoodLabels,
                    onChanged: (v) => setState(() => _likelihood = v ?? _likelihood),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownField(
                    label: 'Consequence',
                    value: _impact,
                    items: kConsequenceScale,
                    labelOverrides: kConsequenceLabels,
                    onChanged: (v) => setState(() => _impact = v ?? _impact),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownField(
                    label: 'Status',
                    value: _status,
                    items: RaidKind.risk.statuses,
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mitigationCtrl,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(color: KColors.text, fontSize: 12.5, height: 1.4),
              decoration: const InputDecoration(
                labelText: 'Treatment',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: KColors.text, fontSize: 12.5, height: 1.4),
              decoration: InputDecoration(
                labelText: 'What changed since the last review',
                hintText: r.statusNote?.trim().isNotEmpty == true
                    ? 'Previously: ${r.statusNote!.trim()}'
                    : 'Optional — replaces the status note',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep() {
    final next = du.formatDate(reviewStamp(_today).next);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _queue.isEmpty
              ? 'Nothing to review.'
              : 'Reviewed $_reviewed · skipped $_skipped',
          style: TextStyle(color: KColors.text, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          _queue.isEmpty
              ? 'No risk in this scope is due a look.'
              : _reviewed == 0
                  ? 'Nothing was changed.'
                  : 'The reviewed risks fall due again on $next. Skipped ones stay behind in Helm.',
          style: TextStyle(color: KColors.textDim, fontSize: 12),
        ),
      ],
    );
  }

  Widget _fact(String k, String? v, {bool warn = false}) {
    if (v == null || v.trim().isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k  ',
            style: TextStyle(color: KColors.textMuted, fontSize: 10.5),
          ),
          TextSpan(
            text: v,
            style: TextStyle(
              color: warn ? KColors.red : KColors.textDim,
              fontSize: 10.5,
            ),
          ),
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

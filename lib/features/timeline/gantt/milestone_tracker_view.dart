import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';

// ─── Status metadata ──────────────────────────────────────────────────────────
const _kStatuses = [
  'not_started', 'on_track', 'at_risk', 'complete', 'overdue',
];
const _kStatusLabels = {
  'not_started': 'Not started',
  'on_track':    'On track',
  'at_risk':     'At risk',
  'complete':    'Complete',
  'overdue':     'Overdue',
};

Widget statusChip(String status) {
  final (label, color, bg) = switch (status) {
    'on_track'    => ('● On track',  KColors.phosphor, KColors.phosDim),
    'at_risk'     => ('▲ At risk',   KColors.amber,    KColors.amberDim),
    'complete'    => ('✓ Complete',  KColors.phosphor, KColors.phosDim),
    'overdue'     => ('! Overdue',   KColors.red,      KColors.redDim),
    _             => ('○ Not started', KColors.textMuted, Colors.transparent),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(3),
      border: bg == Colors.transparent
          ? Border.all(color: KColors.border2)
          : null,
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

// ─── Main widget ──────────────────────────────────────────────────────────────
class MilestoneTrackerView extends StatelessWidget {
  final List<TimelineWorkPackage> wps;
  final Map<String, List<TimelineActivity>> actsByWp;
  final List<String> months;
  final ProgrammeHeader? header;
  final void Function(TimelineActivity, TimelineWorkPackage) onTap;

  const MilestoneTrackerView({
    super.key,
    required this.wps,
    required this.actsByWp,
    required this.months,
    this.header,
    required this.onTap,
  });

  String _monthLabel(int? idx) {
    if (idx == null) return '—';
    if (idx >= 0 && idx < months.length) return months[idx];
    return 'M$idx';
  }

  Color _wpColor(String theme) => switch (theme) {
        'wp1'        => const Color(0xFF3B82F6),
        'wp2'        => const Color(0xFF10B981),
        'wp3'        => const Color(0xFF8B5CF6),
        'wp4'        => const Color(0xFFF59E0B),
        'mpower'     => const Color(0xFF06B6D4),
        'governance' => const Color(0xFF6B7280),
        _            => const Color(0xFF64748B),
      };

  static bool _isMilestoneType(String type) =>
      type == 'milestone' || type == 'hard_deadline' || type == 'gate';

  @override
  Widget build(BuildContext context) {
    // Only show WPs that have at least one milestone/deadline/gate
    final filteredWps = wps.where((wp) {
      final acts = actsByWp[wp.id] ?? [];
      return acts.any((a) => _isMilestoneType(a.activityType));
    }).toList();

    if (filteredWps.isEmpty) {
      return _buildEmptyState();
    }

    return Column(children: [
      // ── Header band ────────────────────────────────────────────────────
      if (header?.hardDeadline != null)
        _HardDeadlineBanner(text: header!.hardDeadline!),

      // ── List ───────────────────────────────────────────────────────────
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 32),
          itemCount: filteredWps.length,
          itemBuilder: (ctx, i) =>
              _buildWpSection(filteredWps[i]),
        ),
      ),
    ]);
  }

  Widget _buildWpSection(TimelineWorkPackage wp) {
    final c    = _wpColor(wp.colourTheme);
    final acts = (actsByWp[wp.id] ?? [])
        .where((a) => _isMilestoneType(a.activityType))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WP header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            border: Border(
              left: BorderSide(color: c, width: 3),
              bottom: const BorderSide(color: KColors.border),
            ),
          ),
          child: Row(children: [
            Text(
              wp.shortCode != null
                  ? '${wp.shortCode} — ${wp.name}'
                  : wp.name,
              style: TextStyle(
                  color: c, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            // Summary counts
            _WpSummaryBadges(acts: acts),
          ]),
        ),
        // Column header (first WP only effectively — or repeat for clarity)
        const _ColumnHeader(),
        // Activity rows
        ...acts.map((act) => _buildMilestoneRow(act, wp)),
      ],
    );
  }

  Widget _buildMilestoneRow(TimelineActivity act, TimelineWorkPackage wp) {
    final c = _wpColor(wp.colourTheme);

    final (icon, iconColor) = switch (act.activityType) {
      'hard_deadline' => ('⚠', KColors.red),
      'gate'          => ('◈', KColors.amber),
      _               => ('◆', c),
    };

    final isHard = act.activityType == 'hard_deadline';

    return InkWell(
      onTap: () => onTap(act, wp),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isHard
              ? const Color(0x08EF4444)
              : KColors.surface,
          border: Border(
            left: isHard
                ? const BorderSide(color: KColors.red, width: 2)
                : BorderSide.none,
            bottom: BorderSide(
                color: KColors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(children: [
          // Icon
          SizedBox(
            width: 24,
            child: Text(icon,
                style: TextStyle(
                    color: iconColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          // Name + badges
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(act.name,
                    style: TextStyle(
                        color: isHard ? KColors.red : KColors.text,
                        fontSize: 12,
                        fontWeight: isHard
                            ? FontWeight.w700
                            : FontWeight.w400)),
              ),
              if (isHard) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: KColors.redDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text('HARD',
                      style: TextStyle(
                          color: KColors.red,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ],
              if (act.isCritical) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: 'Critical path',
                  child: Icon(Icons.priority_high,
                      size: 11, color: KColors.red),
                ),
              ],
            ]),
          ),
          // Month
          SizedBox(
            width: 72,
            child: Text(_monthLabel(act.startMonth),
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 11)),
          ),
          // Owner
          SizedBox(
            width: 130,
            child: Text(act.owner ?? '—',
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          // Status
          SizedBox(
            width: 110,
            child: statusChip(act.status),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('◆', style: TextStyle(color: KColors.textMuted, fontSize: 36)),
        const SizedBox(height: 12),
        const Text('No milestones or deadlines',
            style: TextStyle(
                color: KColors.text, fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text(
            'Add activities with type Milestone, Hard Deadline, or Gate.',
            style: TextStyle(color: KColors.textDim, fontSize: 12)),
      ]),
    );
  }
}

// ─── Column header ────────────────────────────────────────────────────────────
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(
        color: KColors.surface2,
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: const Row(children: [
        SizedBox(width: 24),   // icon
        Expanded(child: Text('MILESTONE / DEADLINE',
            style: TextStyle(
                color: KColors.textMuted, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 0.1))),
        SizedBox(width: 72,
            child: Text('MONTH',
                style: TextStyle(
                    color: KColors.textMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1))),
        SizedBox(width: 130,
            child: Text('OWNER',
                style: TextStyle(
                    color: KColors.textMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1))),
        SizedBox(width: 110,
            child: Text('STATUS',
                style: TextStyle(
                    color: KColors.textMuted, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.1))),
      ]),
    );
  }
}

// ─── Hard deadline banner ─────────────────────────────────────────────────────
class _HardDeadlineBanner extends StatelessWidget {
  final String text;
  const _HardDeadlineBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: KColors.redDim,
        border: Border(bottom: BorderSide(color: KColors.red)),
      ),
      child: Row(children: [
        const Text('⚠  ', style: TextStyle(color: KColors.red, fontSize: 13)),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: KColors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── WP summary badges ────────────────────────────────────────────────────────
class _WpSummaryBadges extends StatelessWidget {
  final List<TimelineActivity> acts;
  const _WpSummaryBadges({required this.acts});

  @override
  Widget build(BuildContext context) {
    final complete   = acts.where((a) => a.status == 'complete').length;
    final atRisk     = acts.where((a) => a.status == 'at_risk').length;
    final overdue    = acts.where((a) => a.status == 'overdue').length;
    final total      = acts.length;

    return Row(children: [
      if (complete > 0)
        _badge('$complete/$total', KColors.phosphor, KColors.phosDim),
      if (atRisk > 0) ...[
        const SizedBox(width: 4),
        _badge('$atRisk at risk', KColors.amber, KColors.amberDim),
      ],
      if (overdue > 0) ...[
        const SizedBox(width: 4),
        _badge('$overdue overdue', KColors.red, KColors.redDim),
      ],
    ]);
  }

  Widget _badge(String label, Color fg, Color bg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(3)),
        child: Text(label,
            style: TextStyle(
                color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

// ─── Re-exported constants for use in activity form ───────────────────────────
List<String> get milestoneTrackerStatuses => _kStatuses;
Map<String, String> get milestoneTrackerStatusLabels => _kStatusLabels;

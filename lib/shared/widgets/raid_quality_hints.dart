import 'package:flutter/material.dart';

import '../../core/raid/raid_conversion_service.dart' show RaidKind;
import '../../core/raid/raid_statements.dart';
import '../theme/keel_colors.dart';

/// Live nudges under a RAID description: what the statement is still
/// missing against the house pattern, or a quiet "well-formed" tick.
/// Reads its inputs from controllers so it updates as the PM types.
/// Never blocks saving — it is coaching, not validation.
class RaidQualityHints extends StatelessWidget {
  final RaidKind kind;
  final TextEditingController description;
  final TextEditingController? title;
  final TextEditingController? owner;
  final TextEditingController? counterparty;
  final TextEditingController? validatedBy;
  final TextEditingController? impactStatement;
  /// Non-controller inputs (a date picker's value) — pass the current
  /// value; the parent rebuilds when it changes.
  final String? dueDate;

  const RaidQualityHints({
    super.key,
    required this.kind,
    required this.description,
    this.title,
    this.owner,
    this.counterparty,
    this.validatedBy,
    this.impactStatement,
    this.dueDate,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = Listenable.merge([
      description,
      ?title,
      ?owner,
      ?counterparty,
      ?validatedBy,
      ?impactStatement,
    ]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final text = description.text;
        if (text.trim().isEmpty) {
          return _Pattern(kind: kind);
        }
        final hints = raidQualityHints(
          kind,
          description: text,
          title: title?.text,
          owner: owner?.text,
          dueDate: dueDate,
          counterparty: counterparty?.text,
          validatedBy: validatedBy?.text,
          impactStatement: impactStatement?.text,
        );
        if (hints.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.check_circle_outline, size: 12, color: KColors.phosphor),
              SizedBox(width: 5),
              Text('Well-formed: cause, event and impact are all here.',
                  style: TextStyle(color: KColors.phosphor, fontSize: 10.5)),
            ]),
          );
        }
        final structural = hints.where((h) => h.severity == 2).toList();
        final polish = hints.where((h) => h.severity == 1).toList();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final h in structural) _HintRow(h, color: KColors.amber),
            for (final h in polish) _HintRow(h, color: KColors.textDim),
          ]),
        );
      },
    );
  }
}

class _HintRow extends StatelessWidget {
  final RaidQualityHint hint;
  final Color color;
  const _HintRow(this.hint, {required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
                hint.severity == 2
                    ? Icons.radio_button_unchecked
                    : Icons.remove,
                size: 10,
                color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(hint.text,
                style: TextStyle(color: color, fontSize: 10.5, height: 1.3)),
          ),
        ]),
      );
}

/// The target shape, shown while the description is still empty.
class _Pattern extends StatelessWidget {
  final RaidKind kind;
  const _Pattern({required this.kind});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Tooltip(
          message: kRaidStatementWhy[kind] ?? '',
          waitDuration: const Duration(milliseconds: 400),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.edit_note, size: 12, color: KColors.textMuted),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Aim for: ${kRaidStatementPatterns[kind]}',
                  style: const TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      height: 1.3)),
            ),
          ]),
        ),
      );
}

/// Register-row marker: a small amber "IMPROVE" chip when the statement
/// is missing a structural part (cause, event, impact, validation,
/// counterparty…), with the hints in its tooltip. Nothing when the
/// statement passes or only has polish notes, so a good register stays
/// clean. Pass [enabled] false for closed or cascaded rows.
class RaidQualityMarker extends StatelessWidget {
  final RaidKind kind;
  final String description;
  final String? title;
  final String? owner;
  final String? dueDate;
  final String? counterparty;
  final String? validatedBy;
  final String? impactStatement;
  final bool enabled;

  const RaidQualityMarker({
    super.key,
    required this.kind,
    required this.description,
    this.title,
    this.owner,
    this.dueDate,
    this.counterparty,
    this.validatedBy,
    this.impactStatement,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final structural = raidQualityHints(
      kind,
      description: description,
      title: title,
      owner: owner,
      dueDate: dueDate,
      counterparty: counterparty,
      validatedBy: validatedBy,
      impactStatement: impactStatement,
    ).where((h) => h.severity == 2).toList();
    if (structural.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      richMessage: TextSpan(children: [
        const TextSpan(
            text: 'Statement could be stronger:\n',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (final h in structural) TextSpan(text: '• ${h.text}\n'),
        TextSpan(
            text: '\nAim for: ${kRaidStatementPatterns[kind]}',
            style: const TextStyle(fontStyle: FontStyle.italic)),
      ]),
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.amberDim,
          border: Border.all(color: KColors.amber, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.edit_note, size: 10, color: KColors.amber),
          const SizedBox(width: 3),
          Text('IMPROVE · ${structural.length}',
              style: const TextStyle(
                  color: KColors.amber,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
        ]),
      ),
    );
  }
}

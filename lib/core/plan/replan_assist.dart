/// The AI half of Re-plan: given the engine's mechanical move for one
/// activity and what Keel knows around it, ask the model whether the
/// duration still holds, why, and what to watch. The model never does
/// date maths — it answers in whole months or days of *extra* time, and
/// [parseReplanAdvice] clamps anything outside the allowed range. Pure
/// Dart: prompt in, advice out, unit-tested without a model.
library;

import 'dart:convert';

import 'date_precision.dart' show monthSpanForDates;
import 'replan.dart';

class ReplanAssistPrompt {
  final String system;
  final String user;
  const ReplanAssistPrompt({required this.system, required this.user});
}

/// What the model said about one move, already validated.
class ReplanAdvice {
  /// Extra time the model thinks the activity needs beyond the engine's
  /// proposal. Zero means it agrees. Months for month-level rows, days
  /// for dated rows; never both.
  final ReplanExtension extension;

  /// 'low' | 'medium' | 'high' — how sure the model is of the extension.
  final String confidence;

  /// One or two steering-committee sentences on why the dates are what
  /// they are.
  final String rationale;

  /// Short things to watch: a dependency, a risk, a resourcing gap.
  final List<String> watch;

  const ReplanAdvice({
    required this.extension,
    required this.confidence,
    required this.rationale,
    required this.watch,
  });

  bool get agrees => extension.isZero;
}

/// Upper bounds on what the model may add, so a hallucinated "18" can't
/// rewrite a quarter.
const int kReplanMaxExtraMonths = 6;
const int kReplanMaxExtraDays = 180;

const String _kPersona =
    'You are helping a project manager re-plan a delivery schedule. An '
    'activity that had not started by its planned date has been slid '
    'forward mechanically, keeping its original duration and respecting '
    'dependencies. Your job is to judge whether that duration still holds '
    'given what is known about the work, and to explain the new dates in '
    'plain English suitable for a steering committee. Never invent facts '
    '(dates, names, systems) that are not in the context given. Do not '
    'change the start — only say whether the activity needs more time. '
    'Answer ONLY with a single JSON object and nothing else.';

String _system(String? projectContext) =>
    projectContext == null || projectContext.trim().isEmpty
        ? _kPersona
        : '$projectContext\n\n---\n\n$_kPersona';

String _line(String label, String? value) =>
    value == null || value.trim().isEmpty ? '' : '$label: ${value.trim()}\n';

/// Builds the prompt for one change. [predecessors] and [successors] are
/// "Name (type)" strings; [linkedItems] are RAID items tied to the row's
/// variance ("R3 Vendor slips — open, likely/major"); [openActions] is
/// how many actions sit under the activity.
ReplanAssistPrompt replanAssistPrompt({
  required ReplanChange change,
  required DateTime month0,
  required String? workPackageName,
  required List<String> predecessors,
  required List<String> successors,
  required List<String> linkedItems,
  required int openActions,
  String? projectContext,
}) {
  final c = change;
  final dated = c.toEndDate != null;
  final from = replanSpanLabel(
      startMonth: c.fromStartMonth, endMonth: c.fromEndMonth,
      startDate: c.fromStartDate, endDate: c.fromEndDate, month0: month0);
  final to = replanSpanLabel(
      startMonth: c.toStartMonth, endMonth: c.toEndMonth,
      startDate: c.toStartDate, endDate: c.toEndDate, month0: month0);
  final unit = dated ? 'days' : 'months';
  final max = dated ? kReplanMaxExtraDays : kReplanMaxExtraMonths;

  final b = StringBuffer()
    ..write(_line('Activity', c.name))
    ..write(_line('Work package', workPackageName))
    ..write(_line('Type', c.activity.activityType.replaceAll('_', ' ')))
    ..write(_line('Status', c.activity.status.replaceAll('_', ' ')))
    ..write(_line('Planned', from))
    ..write(_line('Proposed by the engine', to))
    ..write(_line('Why it moved', c.reasons.join(' ')))
    ..write(_line('Notes on the activity', c.activity.notes))
    ..write(_line('Depends on', predecessors.isEmpty ? null : predecessors.join('; ')))
    ..write(_line('Gates', successors.isEmpty ? null : successors.join('; ')))
    ..write(_line('Linked risks and issues',
        linkedItems.isEmpty ? null : linkedItems.join('; ')))
    ..write(_line('Open actions under it',
        openActions == 0 ? null : '$openActions'))
    ..write('\n')
    ..write('Judge the proposed dates. Reply with exactly this JSON:\n')
    ..write('{"extra_$unit": <integer 0..$max, 0 if the duration still holds>, ')
    ..write('"confidence": "low" | "medium" | "high", ')
    ..write('"rationale": "<one or two sentences a steering committee would accept>", ')
    ..write('"watch": ["<short thing to watch>", ...] (at most 3, may be empty)}\n')
    ..write('Give extra time only for a reason visible in the context above: '
        'a late dependency, an open risk or issue on this work, a note that '
        'says the scope grew. Otherwise answer 0.');

  return ReplanAssistPrompt(system: _system(projectContext), user: b.toString());
}

/// Parses the model's reply. Tolerates fences, prose around the object
/// and a `<think>` block already stripped by the client. Returns null
/// when no usable object is there. Out-of-range extras are clamped;
/// negative ones become zero.
ReplanAdvice? parseReplanAdvice(String raw, {required bool dated}) {
  final obj = firstJsonObject(raw);
  if (obj == null) return null;
  int extra(String key, int max) {
    final v = obj[key];
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return n < 0 ? 0 : (n > max ? max : n);
  }
  final months = dated ? 0 : extra('extra_months', kReplanMaxExtraMonths);
  final days = dated ? extra('extra_days', kReplanMaxExtraDays) : 0;
  final conf = '${obj['confidence'] ?? 'low'}'.toLowerCase().trim();
  final watchRaw = obj['watch'];
  final watch = watchRaw is List
      ? watchRaw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).take(3).toList()
      : const <String>[];
  final rationale = '${obj['rationale'] ?? ''}'.trim();
  return ReplanAdvice(
    extension: ReplanExtension(months: months, days: days),
    confidence: const {'low', 'medium', 'high'}.contains(conf) ? conf : 'low',
    rationale: rationale,
    watch: watch,
  );
}

/// The first complete JSON object in a model reply, tolerating fences
/// and prose around it. Shared by every JSON-answering prompt.
Map<String, dynamic>? firstJsonObject(String raw) {
  var text = raw.trim();
  // Strip ```json fences.
  text = text.replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceAll(RegExp(r'\s*```$'), '');
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (ch == '\\') {
        i++;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        try {
          final decoded = jsonDecode(text.substring(start, i + 1));
          return decoded is Map<String, dynamic> ? decoded : null;
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

// ─── Sub-task suggestions ─────────────────────────────────────────────────

/// One task the model proposed: a name and a relative weight (1..5)
/// that [partitionSpan] turns into a slice of the parent's window.
class SuggestedTask {
  final String name;
  final int weight;
  const SuggestedTask({required this.name, required this.weight});
}

const int kReplanMaxSubtasks = 6;

/// Asks for a short, ordered breakdown of the activity. No dates: the
/// model only says what the pieces are and roughly how big each is.
ReplanAssistPrompt replanSubtaskPrompt({
  required ReplanChange change,
  required DateTime month0,
  required String? workPackageName,
  required List<String> linkedItems,
  String? projectContext,
}) {
  final c = change;
  final to = replanSpanLabel(
      startMonth: c.toStartMonth, endMonth: c.toEndMonth,
      startDate: c.toStartDate, endDate: c.toEndDate, month0: month0);
  final b = StringBuffer()
    ..write(_line('Activity', c.name))
    ..write(_line('Work package', workPackageName))
    ..write(_line('Window', to))
    ..write(_line('Notes on the activity', c.activity.notes))
    ..write(_line('Linked risks and issues',
        linkedItems.isEmpty ? null : linkedItems.join('; ')))
    ..write('\n')
    ..write('Break this activity into 3 to $kReplanMaxSubtasks sequential tasks '
        'in delivery order, each named in at most 8 words, with a relative '
        'size from 1 (small) to 5 (large). Use only what the context says '
        'the work involves; do not invent systems or parties. Reply with '
        'exactly this JSON:\n')
    ..write('{"tasks": [{"name": "<task>", "weight": <1..5>}, ...]}');
  return ReplanAssistPrompt(
    system: _system(projectContext).replaceFirst(
        'Your job is to judge whether that duration still holds',
        'Your job here is to break the activity into its delivery steps'),
    user: b.toString(),
  );
}

/// Parses the model's task list. Blank names are dropped, weights are
/// clamped to 1..5, and at most [kReplanMaxSubtasks] come back.
List<SuggestedTask> parseReplanSubtasks(String raw) {
  final obj = firstJsonObject(raw);
  final list = obj?['tasks'];
  if (list is! List) return const [];
  final out = <SuggestedTask>[];
  for (final e in list) {
    if (e is! Map) continue;
    final name = '${e['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final w = e['weight'];
    final n = w is num ? w.toInt() : int.tryParse('$w') ?? 1;
    out.add(SuggestedTask(name: name, weight: n < 1 ? 1 : (n > 5 ? 5 : n)));
    if (out.length == kReplanMaxSubtasks) break;
  }
  return out;
}

/// A slice of the parent window for one task, in both units.
class TaskSpan {
  final int? startMonth;
  final int? endMonth;
  final String? startDate;
  final String? endDate;
  const TaskSpan({this.startMonth, this.endMonth, this.startDate, this.endDate});
}

/// Divides the parent's window among [weights], in order, so the tasks
/// run back to back and together cover the whole window. Month-level
/// windows are split by months (every task gets at least the month it
/// starts in, so short windows with many tasks overlap rather than
/// vanish); dated windows are split by days and their months derived.
List<TaskSpan> partitionSpan({
  required int? startMonth,
  required int? endMonth,
  required String? startDate,
  required String? endDate,
  required List<int> weights,
  required DateTime month0,
}) {
  if (weights.isEmpty) return const [];
  final total = weights.fold<int>(0, (a, b) => a + (b < 1 ? 1 : b));
  final sd = startDate != null ? DateTime.tryParse(startDate) : null;
  final ed = endDate != null ? DateTime.tryParse(endDate) : null;

  if (sd != null && ed != null && !ed.isBefore(sd)) {
    final s = DateTime.utc(sd.year, sd.month, sd.day);
    final days = DateTime.utc(ed.year, ed.month, ed.day).difference(s).inDays + 1;
    final out = <TaskSpan>[];
    var cum = 0;
    var cursor = 0; // day offset of the next task's start
    for (var i = 0; i < weights.length; i++) {
      cum += weights[i] < 1 ? 1 : weights[i];
      var endOff = (days * cum / total).floor() - 1;
      if (i == weights.length - 1) endOff = days - 1;
      if (endOff < cursor) endOff = cursor;
      final ts = s.add(Duration(days: cursor));
      final te = s.add(Duration(days: endOff));
      final span = monthSpanForDates(
          startDate: _isoDay(ts), endDate: _isoDay(te),
          month0Date: _isoDay(month0));
      out.add(TaskSpan(
        startMonth: span?.startMonth,
        endMonth: span?.endMonth,
        startDate: _isoDay(ts),
        endDate: _isoDay(te),
      ));
      cursor = endOff + 1 > days - 1 ? days - 1 : endOff + 1;
    }
    return out;
  }

  if (startMonth == null) return const [];
  final e = endMonth ?? startMonth;
  final months = e - startMonth + 1;
  final out = <TaskSpan>[];
  var cum = 0;
  var cursor = 0;
  for (var i = 0; i < weights.length; i++) {
    cum += weights[i] < 1 ? 1 : weights[i];
    var endOff = (months * cum / total).floor() - 1;
    if (i == weights.length - 1) endOff = months - 1;
    if (endOff < cursor) endOff = cursor;
    out.add(TaskSpan(
      startMonth: startMonth + cursor,
      endMonth: startMonth + endOff,
    ));
    cursor = endOff + 1 > months - 1 ? months - 1 : endOff + 1;
  }
  return out;
}

String _isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

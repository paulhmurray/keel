import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/context_builder.dart';

void main() {
  late AppDatabase db;
  late ContextBuilder builder;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'p1', name: 'Horizon'),
    );
    builder = ContextBuilder(db);
  });

  tearDown(() async => db.close());

  Future<void> addCard({
    required String id,
    required String band,
    required String title,
    String? body,
    String? linkedType,
  }) {
    return db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
      id: id,
      projectId: 'p1',
      title: title,
      body: Value(body),
      band: Value(band),
      linkedItemType: Value(linkedType),
      linkedItemId: Value(linkedType == null ? null : 'x'),
    ));
  }

  test('Canvas section absent when no cards', () async {
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, isNot(contains('## Canvas')));
  });

  test('Canvas section includes This Week titles and bodies', () async {
    await addCard(
      id: 'a',
      band: 'this_week',
      title: 'Brief CEO',
      body: 'Pre-board prep',
      linkedType: 'action',
    );
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, contains('## Canvas — Strategic Thinking'));
    expect(prompt, contains('### This Week'));
    expect(prompt, contains('Brief CEO'));
    expect(prompt, contains('Pre-board prep'));
    expect(prompt, contains('[action]'));
  });

  test('This Week body truncated past 240 chars', () async {
    final longBody = 'x' * 400;
    await addCard(
      id: 'a',
      band: 'this_week',
      title: 'Long card',
      body: longBody,
    );
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt, contains('…'));
    final lines = prompt
        .split('\n')
        .where((l) => l.startsWith('  x'))
        .toList();
    expect(lines, isNotEmpty);
    // Truncated preview line is 240 chars of body + the ellipsis.
    expect(lines.first.length, lessThanOrEqualTo(2 + 241));
  });

  test('Next 30 Days shows only titles, capped at 10', () async {
    for (var i = 0; i < 12; i++) {
      await addCard(
        id: 'n$i',
        band: 'next_30_days',
        title: 'Item $i',
        body: 'should not appear',
      );
    }
    final prompt = await builder.buildSystemPrompt('p1');
    final n30 = _extractSection(prompt, '### Next 30 Days');
    expect(n30, isNotEmpty);
    final bullets =
        n30.split('\n').where((l) => l.startsWith('- ')).toList();
    expect(bullets.length, 10);
    expect(n30, isNot(contains('should not appear')));
  });

  test('Horizon capped at 5', () async {
    for (var i = 0; i < 8; i++) {
      await addCard(
        id: 'h$i',
        band: 'horizon',
        title: 'Horizon $i',
      );
    }
    final prompt = await builder.buildSystemPrompt('p1');
    final hz = _extractSection(prompt, '### Horizon');
    final bullets =
        hz.split('\n').where((l) => l.startsWith('- ')).toList();
    expect(bullets.length, 5);
  });

  test('Canvas section warns against verbatim use in stakeholder docs',
      () async {
    await addCard(id: 'a', band: 'this_week', title: 'X');
    final prompt = await builder.buildSystemPrompt('p1');
    expect(prompt.toLowerCase(), contains('never quote verbatim'));
  });

  test('buildContextSummary reports total canvas card count', () async {
    await addCard(id: 'a', band: 'this_week', title: 'A');
    await addCard(id: 'b', band: 'next_30_days', title: 'B');
    await addCard(id: 'c', band: 'horizon', title: 'C');
    final summary = await builder.buildContextSummary('p1');
    final canvas =
        summary.where((s) => s.$1 == 'Canvas cards').toList();
    expect(canvas.single.$2, 3);
  });

  test('buildContextSummary omits canvas line when no cards', () async {
    final summary = await builder.buildContextSummary('p1');
    final canvas = summary.where((s) => s.$1 == 'Canvas cards');
    expect(canvas, isEmpty);
  });
}

/// Returns the substring of [prompt] from [header] up to the next blank
/// line (i.e. the section content).
String _extractSection(String prompt, String header) {
  final lines = prompt.split('\n');
  final start = lines.indexOf(header);
  if (start < 0) return '';
  final end = lines.indexWhere((l) => l.startsWith('### ') || l.startsWith('## '),
      start + 1);
  final slice = end < 0 ? lines.sublist(start) : lines.sublist(start, end);
  return slice.join('\n');
}

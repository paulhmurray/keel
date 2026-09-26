import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/programme/source_filter.dart';

typedef _Row = ({String id, String? src, DateTime? esc});

void main() {
  final rows = <_Row>[
    (id: 'native', src: null, esc: null),
    (id: 'a-esc', src: 'projA', esc: DateTime(2026, 9, 1)),
    (id: 'a-quiet', src: 'projA', esc: null),
    (id: 'b-quiet', src: 'projB', esc: null),
  ];
  List<String> ids(SourceFilter f) => f
      .apply<_Row>(rows,
          sourceProjectId: (r) => r.src, escalatedAt: (r) => r.esc)
      .map((r) => r.id)
      .toList();

  test('all shows everything', () {
    expect(ids(SourceFilter.all), ['native', 'a-esc', 'a-quiet', 'b-quiet']);
    expect(SourceFilter.all.isAll, isTrue);
  });
  test('programme only keeps native rows', () {
    expect(ids(const SourceFilter(sourceId: SourceFilter.kProgrammeOnly)),
        ['native']);
  });
  test('a project id keeps that project\'s cascaded rows', () {
    expect(ids(const SourceFilter(sourceId: 'projA')), ['a-esc', 'a-quiet']);
  });
  test('escalated only drops unflagged cascaded rows but keeps native ones',
      () {
    expect(ids(const SourceFilter(escalatedOnly: true)), ['native', 'a-esc']);
    expect(ids(const SourceFilter(sourceId: 'projA', escalatedOnly: true)),
        ['a-esc']);
  });
  test('copyWith clears the source without touching the toggle', () {
    final f = const SourceFilter(sourceId: 'projA', escalatedOnly: true)
        .copyWith(clearSource: true);
    expect(f.sourceId, isNull);
    expect(f.escalatedOnly, isTrue);
  });
  test('sourcesIn lists contributing projects once, in first-seen order', () {
    expect(SourceFilter.sourcesIn<_Row>(rows, sourceProjectId: (r) => r.src),
        ['projA', 'projB']);
  });
}

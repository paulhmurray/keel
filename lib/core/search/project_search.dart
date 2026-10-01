/// Project-wide find: one query reaches people, every register, the plan
/// and the sections themselves.
///
/// The index is built once per palette open from the current project's
/// rows, then filtered and ranked in memory. Matching and ranking are
/// pure Dart so they are unit-tested without a database;
/// [ProjectSearchIndex.load] is the thin DAO glue. The palette shows the
/// hits; the shell decides what "open" means for each kind.
library;

import '../database/database.dart';
import '../shell/landing.dart';

/// What a hit is. Order here is the display order in the palette.
enum SearchKind {
  section,
  person,
  risk,
  issue,
  assumption,
  dependency,
  action,
  decision,
  milestone,
  planActivity,
  workstream,
  glossary,
}

extension SearchKindExt on SearchKind {
  String get label => switch (this) {
        SearchKind.section => 'Go to',
        SearchKind.person => 'People',
        SearchKind.risk => 'Risks',
        SearchKind.issue => 'Issues',
        SearchKind.assumption => 'Assumptions',
        SearchKind.dependency => 'Dependencies',
        SearchKind.action => 'Actions',
        SearchKind.decision => 'Decisions',
        SearchKind.milestone => 'Milestones',
        SearchKind.planActivity => 'Plan activities',
        SearchKind.workstream => 'Workstreams',
        SearchKind.glossary => 'Glossary',
      };
}

/// One thing the palette can show and the shell can open.
class SearchHit {
  final SearchKind kind;
  final String id;
  final String? ref;
  final String title;

  /// Second line: owner, status, role — whatever helps pick without
  /// opening.
  final String? subtitle;

  /// Everything the matcher may look in, lower-cased at build time.
  final String haystack;

  /// The typed row (Risk, Person, …) so the shell can hand it straight
  /// to a form dialog without a second fetch. Null for sections.
  final Object? payload;

  /// Shell nav index this hit lives under.
  final int navIndex;

  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.haystack,
    required this.navIndex,
    this.ref,
    this.subtitle,
    this.payload,
  });

  @override
  String toString() => 'SearchHit(${kind.name} $id "$title")';
}

/// A navigable section, searchable by name and a few aliases so "raid",
/// "risks" and "register" all reach RAID.
class SearchableSection {
  final String label;
  final int navIndex;
  final List<String> keywords;
  final bool programmeOnly;

  const SearchableSection(
    this.label,
    this.navIndex, {
    this.keywords = const [],
    this.programmeOnly = false,
  });
}

const List<SearchableSection> kSearchableSections = [
  SearchableSection('Helm', kNavHelm, keywords: ['my day', 'today', 'home']),
  SearchableSection('Overview', kNavOverview,
      keywords: ['programme', 'portfolio'], programmeOnly: true),
  SearchableSection('Canvas', 1, keywords: ['cards', 'quick capture']),
  SearchableSection('Plan', 12, keywords: ['gantt', 'timeline', 'schedule']),
  SearchableSection('Status', 13, keywords: ['rag', 'dashboard', 'report']),
  SearchableSection('Charter', 14, keywords: ['scope', 'objectives']),
  SearchableSection('Finance', 15, keywords: ['budget', 'money', 'cost']),
  SearchableSection('RAID', 2,
      keywords: ['risks', 'assumptions', 'issues', 'dependencies', 'register']),
  SearchableSection('Decisions', 3, keywords: ['decision log']),
  SearchableSection('People', 4,
      keywords: ['stakeholders', 'team', 'vendors', 'contacts']),
  SearchableSection('Actions', 5, keywords: ['tasks', 'todo']),
  SearchableSection('Inbox', 6, keywords: ['triage']),
  SearchableSection('Context', 7, keywords: ['documents', 'glossary', 'entries']),
  SearchableSection('Reports', 8, keywords: ['export', 'pdf']),
  SearchableSection('Journal', 10, keywords: ['notes', 'diary', 'log']),
  SearchableSection('Playbook', 11, keywords: ['stages', 'checklist']),
  SearchableSection('Settings', 9, keywords: ['preferences', 'sync', 'llm']),
];

// ─── Matching and ranking ────────────────────────────────────────────────

/// Splits a query into lower-cased words, dropping blanks.
List<String> queryWords(String query) =>
    query.toLowerCase().split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);

/// True when every word of [query] appears somewhere in [haystack]
/// (both compared lower-cased). An empty query matches everything.
bool matchesAllWords(String haystack, String query) {
  final words = queryWords(query);
  if (words.isEmpty) return true;
  final hay = haystack.toLowerCase();
  return words.every(hay.contains);
}

/// Higher is better. Tiers, not a fuzzy distance: the user typed a ref,
/// or the start of a name, or a word from the body — in that order of
/// intent.
int scoreHit(SearchHit hit, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final ref = (hit.ref ?? '').toLowerCase();
  final title = hit.title.toLowerCase();
  if (ref.isNotEmpty && ref == q) return 100;
  if (title == q) return 90;
  if (ref.isNotEmpty && ref.startsWith(q)) return 70;
  if (title.startsWith(q)) return 60;
  if (title.contains(q)) return 40;
  // Every word present somewhere in the title (any order).
  if (queryWords(q).every(title.contains)) return 30;
  return 10;
}

/// Filters [candidates] to those matching every word of [query] and
/// orders them best-first. Stable within a score by title so the list
/// doesn't jump as the user types.
List<SearchHit> rankHits(Iterable<SearchHit> candidates, String query) {
  final q = query.trim();
  final matched = candidates
      .where((h) => matchesAllWords(h.haystack, q))
      .map((h) => (hit: h, score: scoreHit(h, q)))
      .toList()
    ..sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return a.hit.title.toLowerCase().compareTo(b.hit.title.toLowerCase());
    });
  return matched.map((m) => m.hit).toList();
}

/// Ranked hits grouped by kind in display order, each group best-first.
Map<SearchKind, List<SearchHit>> groupHits(List<SearchHit> ranked) {
  final out = <SearchKind, List<SearchHit>>{};
  for (final h in ranked) {
    (out[h.kind] ??= <SearchHit>[]).add(h);
  }
  return {
    for (final k in SearchKind.values)
      if (out.containsKey(k)) k: out[k]!,
  };
}

// ─── Index ───────────────────────────────────────────────────────────────

class ProjectSearchIndex {
  final List<SearchHit> hits;
  const ProjectSearchIndex(this.hits);

  /// Ranked matches for [query]. With an empty query, just the sections —
  /// so the palette doubles as a "go to" menu before the user types.
  List<SearchHit> search(String query) {
    if (query.trim().isEmpty) {
      return hits.where((h) => h.kind == SearchKind.section).toList();
    }
    return rankHits(hits, query);
  }

  static List<SearchHit> sectionHits({required bool isProgramme}) => [
        for (final s in kSearchableSections)
          if (!s.programmeOnly || isProgramme)
            SearchHit(
              kind: SearchKind.section,
              id: 'section:${s.navIndex}',
              title: s.label,
              haystack: _hay([s.label, ...s.keywords]),
              navIndex: s.navIndex,
            ),
      ];

  /// Builds the index from already-fetched rows. Pure; see [load].
  static ProjectSearchIndex build({
    required bool isProgramme,
    List<Person> persons = const [],
    List<Risk> risks = const [],
    List<Issue> issues = const [],
    List<Assumption> assumptions = const [],
    List<ProgramDependency> dependencies = const [],
    List<ProjectAction> actions = const [],
    List<Decision> decisions = const [],
    List<Milestone> milestones = const [],
    List<TimelineActivity> planActivities = const [],
    List<Workstream> workstreams = const [],
    List<GlossaryEntry> glossary = const [],
  }) {
    final hits = <SearchHit>[
      ...sectionHits(isProgramme: isProgramme),
      for (final p in persons)
        SearchHit(
          kind: SearchKind.person,
          id: p.id,
          title: p.name,
          subtitle: _join([p.role, p.organisation]),
          haystack: _hay([p.name, p.role, p.organisation, p.email,
              p.teamsHandle, p.personType]),
          payload: p,
          navIndex: 4,
        ),
      for (final r in risks)
        SearchHit(
          kind: SearchKind.risk,
          id: r.id,
          ref: r.ref,
          title: _titleOr(r.title, r.description),
          subtitle: _join([r.owner, r.status]),
          haystack: _hay([r.ref, r.title, r.description, r.owner,
              r.assignee, r.mitigation, r.status]),
          payload: r,
          navIndex: 2,
        ),
      for (final i in issues)
        SearchHit(
          kind: SearchKind.issue,
          id: i.id,
          ref: i.ref,
          title: _titleOr(i.title, i.description),
          subtitle: _join([i.owner, i.status]),
          haystack: _hay([i.ref, i.title, i.description, i.owner,
              i.impactStatement, i.status]),
          payload: i,
          navIndex: 2,
        ),
      for (final a in assumptions)
        SearchHit(
          kind: SearchKind.assumption,
          id: a.id,
          ref: a.ref,
          title: a.description,
          subtitle: _join([a.owner, a.status]),
          haystack: _hay([a.ref, a.description, a.owner, a.status]),
          payload: a,
          navIndex: 2,
        ),
      for (final d in dependencies)
        SearchHit(
          kind: SearchKind.dependency,
          id: d.id,
          ref: d.ref,
          title: d.description,
          subtitle: _join([d.counterparty, d.owner, d.status]),
          haystack: _hay([d.ref, d.description, d.counterparty, d.owner,
              d.rationale, d.status]),
          payload: d,
          navIndex: 2,
        ),
      for (final a in actions)
        SearchHit(
          kind: SearchKind.action,
          id: a.id,
          ref: a.ref,
          title: a.description,
          subtitle: _join([a.owner, a.status, a.dueDate]),
          haystack: _hay([a.ref, a.description, a.owner, a.status]),
          payload: a,
          navIndex: 5,
        ),
      for (final d in decisions)
        SearchHit(
          kind: SearchKind.decision,
          id: d.id,
          ref: d.ref,
          title: d.description,
          subtitle: _join([d.decisionMaker, d.status]),
          haystack: _hay([d.ref, d.description, d.decisionMaker,
              d.rationale, d.outcome, d.status]),
          payload: d,
          navIndex: 3,
        ),
      for (final m in milestones)
        SearchHit(
          kind: SearchKind.milestone,
          id: m.id,
          title: m.name,
          subtitle: _join([m.date, m.status]),
          haystack: _hay([m.name, m.notes, m.status, 'milestone']),
          payload: m,
          navIndex: 12,
        ),
      for (final a in planActivities)
        SearchHit(
          kind: SearchKind.planActivity,
          id: a.id,
          title: a.name,
          subtitle: _join([a.owner, a.status]),
          haystack: _hay([a.name, a.owner, a.cellLabel, a.notes, a.status]),
          payload: a,
          navIndex: 12,
        ),
      for (final w in workstreams)
        SearchHit(
          kind: SearchKind.workstream,
          id: w.id,
          title: w.name,
          subtitle: _join([w.lead, w.status]),
          haystack: _hay([w.name, w.lane, w.lead, w.status, 'workstream']),
          payload: w,
          navIndex: 12,
        ),
      for (final g in glossary)
        SearchHit(
          kind: SearchKind.glossary,
          id: g.id,
          title: g.acronym != null && g.acronym!.isNotEmpty
              ? '${g.name} (${g.acronym})'
              : g.name,
          subtitle: _join([g.type, g.owner]),
          haystack: _hay([g.name, g.acronym, g.description, g.type,
              g.owner, g.environment]),
          payload: g,
          navIndex: 7,
        ),
    ];
    return ProjectSearchIndex(hits);
  }

  /// Fetches every searchable table for [projectId] and builds the index.
  static Future<ProjectSearchIndex> load(
    AppDatabase db,
    String projectId, {
    required bool isProgramme,
  }) async {
    final r = await Future.wait<Object>([
      db.peopleDao.getPersonsForProject(projectId),
      db.raidDao.getRisksForProject(projectId),
      db.raidDao.getIssuesForProject(projectId),
      db.raidDao.getAssumptionsForProject(projectId),
      db.raidDao.getDependenciesForProject(projectId),
      db.actionsDao.getActionsForProject(projectId),
      db.decisionsDao.getDecisionsForProject(projectId),
      db.milestonesDao.getForProject(projectId),
      db.programmeGanttDao.getActivitiesForProject(projectId),
      db.workstreamsDao.getForProject(projectId),
      db.glossaryDao.getForProject(projectId),
    ]);
    return build(
      isProgramme: isProgramme,
      persons: r[0] as List<Person>,
      risks: r[1] as List<Risk>,
      issues: r[2] as List<Issue>,
      assumptions: r[3] as List<Assumption>,
      dependencies: r[4] as List<ProgramDependency>,
      actions: r[5] as List<ProjectAction>,
      decisions: r[6] as List<Decision>,
      milestones: r[7] as List<Milestone>,
      planActivities: r[8] as List<TimelineActivity>,
      workstreams: r[9] as List<Workstream>,
      glossary: r[10] as List<GlossaryEntry>,
    );
  }
}

String _hay(List<String?> parts) => parts
    .where((p) => p != null && p.trim().isNotEmpty)
    .map((p) => p!.trim())
    .join(' ')
    .toLowerCase();

String? _join(List<String?> parts) {
  final kept = parts.where((p) => p != null && p.trim().isNotEmpty).toList();
  return kept.isEmpty ? null : kept.map((p) => p!.trim()).join(' · ');
}

String _titleOr(String? title, String description) =>
    (title ?? '').trim().isNotEmpty ? title!.trim() : description;

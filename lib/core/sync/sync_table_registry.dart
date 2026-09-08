/// Single source of truth for which database tables ride in the sync blob.
///
/// The sync pipeline is hand-maintained in THREE places, and a table
/// missing from any of them silently doesn't sync (or its deletions don't
/// propagate):
///   1. JsonExporter — serialize the rows into the export blob
///   2. JsonImporter._import — apply the rows on import
///   3. JsonImporter._clearSyncedTables — clear before import so deletions
///      made on the source device are reflected here
///
/// When you add a table to database.dart you MUST classify it here —
/// `sync_table_registry_test.dart` fails until you do — and, if synced,
/// wire it into all three places above.
///
/// Names are Drift `actualTableName`s (snake_case).
library;

/// Tables carried in the per-project sync/export blob.
const Set<String> syncedTables = {
  'projects',
  'programme_links',
  'programme_overviews',
  'workstreams',
  'workstream_links',
  'workstream_activities',
  'governance_cadences',
  'risks',
  'assumptions',
  'issues',
  'program_dependencies',
  'raid_item_links',
  'decisions',
  'persons',
  'stakeholder_profiles',
  'stakeholder_roles',
  'team_roles',
  'colleague_profiles',
  'milestones',
  'action_categories',
  'project_actions',
  'action_comments',
  'context_entries',
  'glossary_entries',
  'documents',
  'journal_entries',
  'journal_series_defs',
  'journal_entry_links',
  'canvas_cards',
  'canvas_templates',
  'canvas_sequences',
  'status_reports',
  'status_snapshots',
  'timeline_work_packages',
  'timeline_activities',
  'timeline_dependencies',
  'programme_headers',
  'project_scopes',
  'integration_domains',
  'prioritisation_sources',
  'project_charters',
  'programme_overview_states',
  // Finance v1: categories → budgets → lines cleared+reimported in FK
  // order. The audit log rides in the blob too (history survives a
  // machine move); import uses raw upserts so it never re-audits.
  'cost_categories',
  'project_budgets',
  'budget_lines',
  'forecast_snapshots',
  'forecast_lines',
  'actual_lines',
  'financial_audit_log',
  // Helm day plans are GLOBAL (one day spans every project) but still
  // ride in every project's sync blob — there is no per-user channel.
  // Import is guarded per-day by updatedAt (DayPlanDao.applyImportedPlan)
  // instead of clear+reimport, so pulling a stale project can never
  // clobber a newer plan; _clearSyncedTables deliberately skips them.
  'day_plans',
  'day_plan_blocks',
  // Weekly layer — same global/guarded pattern as day plans (per-week
  // updatedAt guard in WeekPlanDao.applyImportedPlan).
  'week_plans',
  'week_plan_objectives',
  // Quarterly layer — same pattern again (per-quarter guard in
  // QuarterPlanDao.applyImportedPlan).
  'quarter_plans',
  'quarter_goals',
  // Playbook: catalog tables are upsert-only on import (shared across
  // projects); the per-project attachment + progress are cleared+reimported.
  'organisations',
  'playbooks',
  'playbook_stages',
  'stage_templates',
  'project_playbooks',
  'project_stage_progresses',
};

/// Tables deliberately NOT in the sync blob, with why.
const Set<String> localOnlyTables = {
  // Same-machine cascade transport queue: the delivery channel between two
  // entities on one install. Cross-machine cascade rides its own encrypted
  // link channel, not the project blob.
  'cascade_items',
  // Mobile-note inbox: fetched from the server's own /inbox endpoint, a
  // separate channel from project blobs.
  'inbox_items',
};

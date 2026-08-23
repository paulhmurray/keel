import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/analytics_provider.dart';
import 'analytics_service.dart';

/// Single source of truth for every event name and property key Keel
/// emits to the analytics sink. Centralising these means:
///   - Grep for an event name returns one definition and every callsite.
///   - Renaming an event is a single-line change.
///   - The PostHog dashboard can rely on stable names without us
///     accidentally introducing variants ("card_created" vs
///     "cardCreated") during refactors.
///
/// Naming rules:
///   - snake_case
///   - subject-first ("template_created", not "created_template")
///   - past-tense verbs ("opened", "promoted", not "open"/"promote")
///   - never include user-authored content
class KeelEvents {
  KeelEvents._();

  // ---- Lifecycle ----------------------------------------------------------
  static const appLaunched = 'app_launched';

  // ---- Navigation ---------------------------------------------------------
  static const sectionOpened = 'section_opened';

  // ---- Item creation ------------------------------------------------------
  // Counts only — no titles or content.
  static const cardCreated = 'card_created';
  static const riskCreated = 'risk_created';
  static const actionCreated = 'action_created';
  static const decisionCreated = 'decision_created';
  static const dependencyCreated = 'dependency_created';
  static const assumptionCreated = 'assumption_created';
  static const issueCreated = 'issue_created';

  // ---- Templates ----------------------------------------------------------
  static const templateCreated = 'template_created';
  static const templateOpened = 'template_opened';
}

/// Property-key constants — same single-source-of-truth idea applied to
/// the event payloads, so the PostHog dashboard sees a stable schema.
class KeelEventProps {
  KeelEventProps._();

  static const version = 'version';
  static const platform = 'platform';
  // Section identifier — one of [KeelSection].
  static const section = 'section';
  // Template type — matches [CanvasTemplateType] strings.
  static const templateType = 'template_type';
  // Source surface for creation events (e.g. card created from
  // quick-capture vs the new-card button). Tag, not free text.
  static const source = 'source';
}

/// Stable identifiers for the shell's top-level sections. Used as the
/// `section` prop value on [KeelEvents.sectionOpened] so the dashboard
/// sees consistent labels even if the displayed strings change.
class KeelSection {
  KeelSection._();

  static const canvas = 'canvas';
  static const plan = 'plan';
  static const status = 'status';
  static const timeline = 'timeline';
  static const raid = 'raid';
  static const decisions = 'decisions';
  static const actions = 'actions';
  static const people = 'people';
  static const reports = 'reports';
  static const journal = 'journal';
  static const settings = 'settings';
  static const inbox = 'inbox';
  static const charter = 'charter';
  static const finance = 'finance';
  static const helm = 'helm';
}

/// Ergonomic helper so call sites can write
/// `context.analytics.track(KeelEvents.cardCreated)` instead of pulling
/// the provider and reaching into its [AnalyticsProvider.service]
/// getter. Keeps the dependency-direction unchanged — call sites still
/// go through the provider tree, they just don't have to spell it out.
///
/// **Resilient to missing provider:** if no AnalyticsProvider is in
/// scope (e.g. a widget test that omits it from its harness), returns
/// a Noop sink rather than throwing. Analytics must never break the
/// app — that's a load-bearing invariant of the whole system.
extension AnalyticsContext on BuildContext {
  AnalyticsService get analytics {
    try {
      return read<AnalyticsProvider>().service;
    } on ProviderNotFoundException {
      return const NoopAnalyticsService();
    }
  }
}

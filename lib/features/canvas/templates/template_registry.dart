import 'package:flutter/material.dart';

/// String IDs for the six canonical template types. These values are
/// what's stored in `CanvasTemplates.templateType`, so do not rename
/// without a data migration.
class CanvasTemplateType {
  static const preMortem = 'pre_mortem';
  static const swot = 'swot';
  static const retrospective = 'retrospective';
  static const stakeholderMap = 'stakeholder_map';
  static const raciMatrix = 'raci_matrix';
  static const userStoryMap = 'user_story_map';
  static const wardleyMap = 'wardley_map';

  static const all = [
    preMortem,
    swot,
    retrospective,
    stakeholderMap,
    raciMatrix,
    userStoryMap,
    wardleyMap,
  ];
}

/// Catalogue entry for a single template type. Drives the
/// "Available Templates" section of the gallery and the per-type view
/// dispatcher (Phase 3 will plug real view widgets in).
class TemplateDefinition {
  final String type; // CanvasTemplateType.*
  final String name; // display name, e.g. "SWOT"
  final String description; // short subtitle in the gallery card
  final IconData icon;
  final String defaultContent; // serialised initial JSON
  final bool supportsFullscreen;

  const TemplateDefinition({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.defaultContent,
    this.supportsFullscreen = false,
  });
}

/// The single source of truth for available template types. Phase 2
/// surfaces these as creatable instances; Phase 3 fills in their
/// per-type view widgets.
///
/// Default-content payloads are intentionally small — each template's
/// view widget will mutate the JSON as the user works.
class TemplateRegistry {
  static const List<TemplateDefinition> available = [
    TemplateDefinition(
      type: CanvasTemplateType.preMortem,
      name: 'Pre-mortem',
      description: 'Imagine failure, then prevent it',
      icon: Icons.warning_amber_outlined,
      defaultContent: '{"goal":"","causes":[]}',
    ),
    TemplateDefinition(
      type: CanvasTemplateType.swot,
      name: 'SWOT',
      description: 'Strengths · Weaknesses · Opportunities · Threats',
      icon: Icons.grid_view_outlined,
      defaultContent:
          '{"strengths":[],"weaknesses":[],"opportunities":[],"threats":[]}',
    ),
    TemplateDefinition(
      type: CanvasTemplateType.retrospective,
      name: 'Retrospective',
      description: 'Start · Stop · Continue · Learn',
      icon: Icons.refresh_outlined,
      defaultContent: '{"start":[],"stop":[],"continue":[],"learn":[]}',
    ),
    TemplateDefinition(
      type: CanvasTemplateType.stakeholderMap,
      name: 'Stakeholder Map',
      description: 'Influence × Interest grid',
      icon: Icons.scatter_plot_outlined,
      defaultContent: '{"stakeholders":[]}',
    ),
    TemplateDefinition(
      type: CanvasTemplateType.raciMatrix,
      name: 'RACI Matrix',
      description: 'Responsibilities at a glance',
      icon: Icons.table_chart_outlined,
      defaultContent: '{"activities":[],"people":[],"assignments":[]}',
    ),
    TemplateDefinition(
      type: CanvasTemplateType.userStoryMap,
      name: 'User Story Map',
      description: 'Jeff Patton structure — activities, tasks, releases',
      icon: Icons.view_week_outlined,
      defaultContent: '{"activities":[],"releases":[],"stories":[]}',
      supportsFullscreen: true,
    ),
    TemplateDefinition(
      type: CanvasTemplateType.wardleyMap,
      name: 'Wardley Map',
      description: 'Value chain × evolution, with dependencies',
      icon: Icons.account_tree_outlined,
      defaultContent: '{"components":[],"dependencies":[]}',
      supportsFullscreen: true,
    ),
  ];

  /// Look up a definition by stored type string. Returns null when the
  /// type isn't in the registry (shouldn't happen at runtime unless a
  /// migration introduces a new type before the registry catches up).
  static TemplateDefinition? byType(String type) {
    for (final def in available) {
      if (def.type == type) return def;
    }
    return null;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../theme/keel_colors.dart';

/// Small "PROJ · <name>" badge shown on cascaded rows on the programme
/// side. Resolves the source project's name from the live project list
/// (accurate same-machine); falls back to a bare "PROJ" when the source
/// project isn't on this machine (cross-machine). Pass [sourceProjectName]
/// when the row already carries a cached name (people / charter) to skip
/// the lookup and stay correct cross-machine.
class CascadedSourceBadge extends StatelessWidget {
  final String? sourceProjectId;
  final String? sourceProjectName;

  const CascadedSourceBadge({
    super.key,
    this.sourceProjectId,
    this.sourceProjectName,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = (sourceProjectName != null &&
            sourceProjectName!.trim().isNotEmpty)
        ? sourceProjectName
        : (sourceProjectId == null
            ? null
            : context
                .watch<ProjectProvider>()
                .projects
                .cast<Project?>()
                .firstWhere((p) => p?.id == sourceProjectId,
                    orElse: () => null)
                ?.name);
    final label = resolved == null ? 'PROJ' : 'PROJ · $resolved';
    return Tooltip(
      message: resolved == null
          ? 'Cascaded from a linked project — read-only'
          : 'Cascaded from project: $resolved — read-only',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 130),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

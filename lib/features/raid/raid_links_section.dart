import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/raid/raid_conversion_service.dart';
import '../../shared/theme/keel_colors.dart';

/// A linkable RAID item / decision, type-agnostic.
class RaidLinkTarget {
  final String type; // RaidKind name
  final String id;
  final String? ref;
  final String description;

  const RaidLinkTarget({
    required this.type,
    required this.id,
    required this.ref,
    required this.description,
  });

  String get label => '${ref ?? type} · $description';
}

/// Every linkable item in the project, across all five registers.
Future<List<RaidLinkTarget>> loadRaidLinkTargets(
    AppDatabase db, String projectId) async {
  final risks = await db.raidDao.getRisksForProject(projectId);
  final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
  final issues = await db.raidDao.getIssuesForProject(projectId);
  final deps = await db.raidDao.getDependenciesForProject(projectId);
  final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
  return [
    for (final r in risks)
      RaidLinkTarget(
          type: 'risk', id: r.id, ref: r.ref, description: r.description),
    for (final a in assumptions)
      RaidLinkTarget(
          type: 'assumption',
          id: a.id,
          ref: a.ref,
          description: a.description),
    for (final i in issues)
      RaidLinkTarget(
          type: 'issue',
          id: i.id,
          ref: i.ref,
          description: i.title ?? i.description),
    for (final d in deps)
      RaidLinkTarget(
          type: 'dependency',
          id: d.id,
          ref: d.ref,
          description: d.description),
    for (final d in decisions)
      RaidLinkTarget(
          type: 'decision',
          id: d.id,
          ref: d.ref,
          description: d.description),
  ];
}

/// "Related items" chips + picker for a RAID item or decision. Links are
/// persisted immediately (they're cross-references, not form fields).
/// Dangling links (target deleted) are silently hidden.
class RaidLinksSection extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final RaidKind itemType;
  final String itemId;
  final bool readOnly;

  const RaidLinksSection({
    super.key,
    required this.db,
    required this.projectId,
    required this.itemType,
    required this.itemId,
    this.readOnly = false,
  });

  @override
  State<RaidLinksSection> createState() => _RaidLinksSectionState();
}

class _RaidLinksSectionState extends State<RaidLinksSection> {
  List<RaidItemLink> _links = const [];
  Map<String, RaidLinkTarget> _targetsById = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await widget.db.raidDao.getLinksForItem(widget.itemId);
    final targets =
        await loadRaidLinkTargets(widget.db, widget.projectId);
    if (!mounted) return;
    setState(() {
      _links = links;
      _targetsById = {for (final t in targets) t.id: t};
    });
  }

  /// The far end of [link] relative to this item.
  String _otherId(RaidItemLink link) =>
      link.fromId == widget.itemId ? link.toId : link.fromId;

  Future<void> _addLink() async {
    final linkedIds = {for (final l in _links) _otherId(l), widget.itemId};
    final candidates = _targetsById.values
        .where((t) => !linkedIds.contains(t.id))
        .toList()
      ..sort((a, b) => (a.ref ?? '').compareTo(b.ref ?? ''));
    final chosen = await showDialog<RaidLinkTarget>(
      context: context,
      builder: (_) => _LinkPickerDialog(candidates: candidates),
    );
    if (chosen == null) return;
    await widget.db.raidDao.insertItemLink(RaidItemLinksCompanion(
      id: Value(const Uuid().v4()),
      projectId: Value(widget.projectId),
      fromType: Value(widget.itemType.name),
      fromId: Value(widget.itemId),
      toType: Value(chosen.type),
      toId: Value(chosen.id),
    ));
    await _load();
  }

  Future<void> _removeLink(RaidItemLink link) async {
    await widget.db.raidDao.deleteItemLink(link.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = [
      for (final l in _links)
        if (_targetsById[_otherId(l)] != null)
          (link: l, target: _targetsById[_otherId(l)]!),
    ];
    if (widget.readOnly && resolved.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RELATED ITEMS',
          style: TextStyle(
            color: KColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in resolved)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: KColors.surface2,
                  border: Border.all(color: KColors.border2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.target.ref ?? r.target.type,
                      style: const TextStyle(
                          color: KColors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        r.target.description,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 10),
                      ),
                    ),
                    if (!widget.readOnly) ...[
                      const SizedBox(width: 5),
                      InkWell(
                        onTap: () => _removeLink(r.link),
                        child: const Icon(Icons.close,
                            size: 11, color: KColors.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            if (!widget.readOnly)
              InkWell(
                onTap: _addLink,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: KColors.border2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_link, size: 12, color: KColors.phosphor),
                      SizedBox(width: 4),
                      Text('Link item',
                          style: TextStyle(
                              color: KColors.phosphor, fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinkPickerDialog extends StatefulWidget {
  final List<RaidLinkTarget> candidates;

  const _LinkPickerDialog({required this.candidates});

  @override
  State<_LinkPickerDialog> createState() => _LinkPickerDialogState();
}

class _LinkPickerDialogState extends State<_LinkPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final visible = widget.candidates
        .where((t) =>
            q.isEmpty ||
            (t.ref?.toLowerCase().contains(q) ?? false) ||
            t.description.toLowerCase().contains(q))
        .toList();

    return AlertDialog(
      title: const Text('Link related item'),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search by ref or description…',
                prefixIcon: Icon(Icons.search, size: 14),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text('No matching items',
                          style: TextStyle(
                              color: KColors.textMuted, fontSize: 12)))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final t = visible[i];
                        return ListTile(
                          dense: true,
                          onTap: () => Navigator.of(context).pop(t),
                          leading: Text(
                            t.ref ?? '—',
                            style: const TextStyle(
                                color: KColors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                          title: Text(
                            t.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: KColors.text, fontSize: 12),
                          ),
                          subtitle: Text(
                            t.type,
                            style: const TextStyle(
                                color: KColors.textMuted, fontSize: 10),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'charter_export_dialog.dart';
import 'charter_section.dart';

class CharterView extends StatelessWidget {
  const CharterView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectProvider = context.watch<ProjectProvider>();
    final projectId = projectProvider.currentProjectId;
    if (projectId == null) {
      return const Center(
        child: Text('Select a project to view its charter.',
            style: TextStyle(color: KColors.textDim)),
      );
    }
    final db = context.read<AppDatabase>();
    return StreamBuilder<ProjectCharter?>(
      stream: db.projectCharterDao.watchForProject(projectId),
      builder: (context, snap) {
        return _CharterBody(
          projectId: projectId,
          projectName: projectProvider.currentProject?.name ?? 'Programme',
          charter: snap.data,
          db: db,
        );
      },
    );
  }
}

class _CharterBody extends StatefulWidget {
  final String projectId;
  final String projectName;
  final ProjectCharter? charter;
  final AppDatabase db;

  const _CharterBody({
    required this.projectId,
    required this.projectName,
    required this.charter,
    required this.db,
  });

  @override
  State<_CharterBody> createState() => _CharterBodyState();
}

class _CharterBodyState extends State<_CharterBody> {
  bool _editing = false;

  late TextEditingController _visionCtrl;
  late TextEditingController _objectivesCtrl;
  late TextEditingController _scopeInCtrl;
  late TextEditingController _scopeOutCtrl;
  late TextEditingController _deliveryCtrl;
  late TextEditingController _successCtrl;
  late TextEditingController _constraintsCtrl;
  late TextEditingController _assumptionsCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.charter);
  }

  void _initControllers(ProjectCharter? c) {
    _visionCtrl = TextEditingController(text: c?.vision ?? '');
    _objectivesCtrl = TextEditingController(text: c?.objectives ?? '');
    _scopeInCtrl = TextEditingController(text: c?.scopeIn ?? '');
    _scopeOutCtrl = TextEditingController(text: c?.scopeOut ?? '');
    _deliveryCtrl = TextEditingController(text: c?.deliveryApproach ?? '');
    _successCtrl = TextEditingController(text: c?.successCriteria ?? '');
    _constraintsCtrl = TextEditingController(text: c?.keyConstraints ?? '');
    _assumptionsCtrl = TextEditingController(text: c?.assumptions ?? '');
  }

  @override
  void didUpdateWidget(_CharterBody old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.charter != old.charter) {
      _disposeControllers();
      _initControllers(widget.charter);
    }
  }

  void _disposeControllers() {
    _visionCtrl.dispose();
    _objectivesCtrl.dispose();
    _scopeInCtrl.dispose();
    _scopeOutCtrl.dispose();
    _deliveryCtrl.dispose();
    _successCtrl.dispose();
    _constraintsCtrl.dispose();
    _assumptionsCtrl.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.charter?.id ?? const Uuid().v4();
    await widget.db.projectCharterDao.upsert(
      ProjectChartersCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        vision: Value(_visionCtrl.text.trim().isEmpty
            ? null
            : _visionCtrl.text.trim()),
        objectives: Value(_objectivesCtrl.text.trim().isEmpty
            ? null
            : _objectivesCtrl.text.trim()),
        scopeIn: Value(_scopeInCtrl.text.trim().isEmpty
            ? null
            : _scopeInCtrl.text.trim()),
        scopeOut: Value(_scopeOutCtrl.text.trim().isEmpty
            ? null
            : _scopeOutCtrl.text.trim()),
        deliveryApproach: Value(_deliveryCtrl.text.trim().isEmpty
            ? null
            : _deliveryCtrl.text.trim()),
        successCriteria: Value(_successCtrl.text.trim().isEmpty
            ? null
            : _successCtrl.text.trim()),
        keyConstraints: Value(_constraintsCtrl.text.trim().isEmpty
            ? null
            : _constraintsCtrl.text.trim()),
        assumptions: Value(_assumptionsCtrl.text.trim().isEmpty
            ? null
            : _assumptionsCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    setState(() => _editing = false);
  }

  void _cancel() {
    _disposeControllers();
    _initControllers(widget.charter);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final projectName = widget.projectName;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.article_outlined,
                color: KColors.amber, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CHARTER · $projectName',
                      style: Theme.of(context).textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis),
                  const Text(
                    'Foundational programme reference.',
                    style: TextStyle(
                        color: KColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_editing) ...[
              ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _cancel,
                child: const Text('Cancel',
                    style: TextStyle(
                        color: KColors.textDim, fontSize: 12)),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.charter == null
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          builder: (_) => CharterExportDialog(
                            projectName: projectName,
                            charter: widget.charter!,
                          ),
                        ),
                icon: const Icon(Icons.download_outlined, size: 14),
                label: const Text('Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.surface2,
                  foregroundColor: KColors.text,
                  side: const BorderSide(color: KColors.border2),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 28),

          if (_editing) ...[
            CharterEditSection(
              label: 'VISION',
              controller: _visionCtrl,
              hint: 'What does programme success look like in one sentence?',
            ),
            CharterEditSection(
              label: 'OBJECTIVES',
              controller: _objectivesCtrl,
              hint: 'Measurable outcomes the programme must deliver.',
              minLines: 4,
            ),
            CharterEditSection(
              label: 'SCOPE — IN SCOPE',
              controller: _scopeInCtrl,
              hint: 'What this programme explicitly covers.',
              minLines: 4,
            ),
            CharterEditSection(
              label: 'SCOPE — OUT OF SCOPE',
              controller: _scopeOutCtrl,
              hint: 'What this programme explicitly does not cover.',
              minLines: 3,
            ),
            CharterEditSection(
              label: 'DELIVERY APPROACH',
              controller: _deliveryCtrl,
              hint: 'How the programme will be delivered (methodology, phases, team structure).',
              minLines: 4,
            ),
            CharterEditSection(
              label: 'SUCCESS CRITERIA',
              controller: _successCtrl,
              hint: 'How will we know we\'ve succeeded?',
              minLines: 3,
            ),
            CharterEditSection(
              label: 'KEY CONSTRAINTS',
              controller: _constraintsCtrl,
              hint: 'Fixed boundaries (budget, time, regulatory, dependencies).',
              minLines: 3,
            ),
            CharterEditSection(
              label: 'ASSUMPTIONS',
              controller: _assumptionsCtrl,
              hint: 'What we are assuming to be true for planning purposes.',
              minLines: 3,
            ),
          ] else ...[
            CharterSection(
              label: 'VISION',
              value: widget.charter?.vision,
            ),
            CharterSection(
              label: 'OBJECTIVES',
              value: widget.charter?.objectives,
            ),
            CharterSection(
              label: 'SCOPE',
              value: widget.charter?.scopeIn,
              subLabel: 'Out of scope:',
              subValue: widget.charter?.scopeOut,
            ),
            CharterSection(
              label: 'DELIVERY APPROACH',
              value: widget.charter?.deliveryApproach,
            ),
            CharterSection(
              label: 'SUCCESS CRITERIA',
              value: widget.charter?.successCriteria,
            ),
            CharterSection(
              label: 'KEY CONSTRAINTS',
              value: widget.charter?.keyConstraints,
            ),
            CharterSection(
              label: 'ASSUMPTIONS',
              value: widget.charter?.assumptions,
            ),
          ],
        ],
      ),
    );
  }
}

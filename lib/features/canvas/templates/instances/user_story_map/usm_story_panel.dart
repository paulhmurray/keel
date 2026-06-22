import 'package:flutter/material.dart';

import '../../../../../shared/theme/keel_colors.dart';
import 'usm_model.dart';

/// Side panel for editing a single story — title, description, estimate
/// (free text like "S/M/L" or "3 days"), tags (chip-input), and
/// acceptance criteria (one bullet per line).
///
/// Lives outside the grid widget so the parent (`UsmView`) owns the
/// selection state. Re-keyed by story id so its controllers reset when
/// the user switches between stories.
class UsmStoryPanel extends StatefulWidget {
  final UsmStory story;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onDescriptionChanged;
  final ValueChanged<String> onEstimateChanged;
  final ValueChanged<List<String>> onTagsChanged;
  final ValueChanged<List<String>> onAcceptanceCriteriaChanged;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const UsmStoryPanel({
    super.key,
    required this.story,
    required this.onTitleChanged,
    required this.onDescriptionChanged,
    required this.onEstimateChanged,
    required this.onTagsChanged,
    required this.onAcceptanceCriteriaChanged,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<UsmStoryPanel> createState() => _UsmStoryPanelState();
}

class _UsmStoryPanelState extends State<UsmStoryPanel> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _estimateCtrl;
  late final TextEditingController _tagInputCtrl;
  late final TextEditingController _acCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.story.title);
    _descCtrl =
        TextEditingController(text: widget.story.description ?? '');
    _estimateCtrl =
        TextEditingController(text: widget.story.estimate ?? '');
    _tagInputCtrl = TextEditingController();
    _acCtrl = TextEditingController(
        text: widget.story.acceptanceCriteria.join('\n'));
  }

  @override
  void didUpdateWidget(covariant UsmStoryPanel old) {
    super.didUpdateWidget(old);
    if (old.story.id != widget.story.id) {
      _titleCtrl.text = widget.story.title;
      _descCtrl.text = widget.story.description ?? '';
      _estimateCtrl.text = widget.story.estimate ?? '';
      _tagInputCtrl.clear();
      _acCtrl.text = widget.story.acceptanceCriteria.join('\n');
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _estimateCtrl.dispose();
    _tagInputCtrl.dispose();
    _acCtrl.dispose();
    super.dispose();
  }

  void _commitTagInput() {
    final value = _tagInputCtrl.text.trim();
    if (value.isEmpty) return;
    // Allow "comma,separated,values" in one go.
    final adds = value
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final next = [
      ...widget.story.tags,
      for (final t in adds)
        if (!widget.story.tags.contains(t)) t,
    ];
    _tagInputCtrl.clear();
    widget.onTagsChanged(next);
  }

  void _removeTag(String tag) {
    widget.onTagsChanged(
        widget.story.tags.where((t) => t != tag).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border:
            Border(left: BorderSide(color: KColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: KColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'STORY',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close,
                      size: 16, color: KColors.textDim),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Title'),
                  _outlinedField(
                    child: TextField(
                      controller: _titleCtrl,
                      maxLines: null,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _fieldDecoration('What is the story?'),
                      onChanged: widget.onTitleChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section('Description'),
                  _outlinedField(
                    child: TextField(
                      controller: _descCtrl,
                      maxLines: 6,
                      minLines: 3,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                      decoration: _fieldDecoration('Free-form context'),
                      onChanged: widget.onDescriptionChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section('Estimate'),
                  _outlinedField(
                    child: TextField(
                      controller: _estimateCtrl,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 13,
                      ),
                      decoration:
                          _fieldDecoration('e.g. S / M / L · or "3 days"'),
                      onChanged: widget.onEstimateChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section('Tags'),
                  if (widget.story.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final tag in widget.story.tags)
                            _TagChip(
                              tag: tag,
                              onRemove: () => _removeTag(tag),
                            ),
                        ],
                      ),
                    ),
                  _outlinedField(
                    child: TextField(
                      controller: _tagInputCtrl,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12.5,
                      ),
                      decoration: _fieldDecoration(
                          'Add tag (Enter or comma to commit)'),
                      onSubmitted: (_) => _commitTagInput(),
                      onChanged: (v) {
                        // Auto-commit on comma typing for the
                        // mid-typing convenience.
                        if (v.endsWith(',')) _commitTagInput();
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section('Acceptance criteria'),
                  _outlinedField(
                    child: TextField(
                      controller: _acCtrl,
                      maxLines: 8,
                      minLines: 4,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                      decoration: _fieldDecoration(
                          'One acceptance criterion per line'),
                      onChanged: (v) {
                        final lines = v
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        widget.onAcceptanceCriteriaChanged(lines);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Delete story'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KColors.red,
                      side: const BorderSide(color: KColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: KColors.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _outlinedField({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(color: KColors.textMuted, fontSize: 12),
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback onRemove;

  const _TagChip({required this.tag, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 1, 2, 1),
      decoration: BoxDecoration(
        color: KColors.amberDim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(3),
        border:
            Border.all(color: KColors.amber.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: const TextStyle(
              color: KColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          InkWell(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.close, size: 12, color: KColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

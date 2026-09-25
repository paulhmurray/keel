import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/llm/llm_client_factory.dart';
import '../../core/llm/raid_assist_prompts.dart';
import '../../providers/settings_provider.dart';
import '../theme/keel_colors.dart';

/// Small "AI draft" affordance for one free-text field.
///
/// Optional by construction: renders nothing unless an LLM API key is
/// configured in Settings. When pressed it builds the prompt (lazily, so
/// the field's current neighbours are included), calls the configured
/// provider, and shows the draft in a review sheet. The user chooses
/// Replace / Append / Discard — the field is never overwritten silently
/// and nothing is persisted until the form itself is saved.
class AiAssistButton extends StatefulWidget {
  final TextEditingController target;
  final Future<RaidAssistPrompt> Function() buildPrompt;
  final String tooltip;

  const AiAssistButton({
    super.key,
    required this.target,
    required this.buildPrompt,
    required this.tooltip,
  });

  @override
  State<AiAssistButton> createState() => _AiAssistButtonState();
}

class _AiAssistButtonState extends State<AiAssistButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _busy = true);
    String draft;
    try {
      final prompt = await widget.buildPrompt();
      final client = LLMClientFactory.fromSettings(settings);
      draft = (await client.complete(
        systemPrompt: prompt.system,
        userMessage: prompt.user,
        maxTokens: 600,
      ))
          .trim();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('AI draft failed: $e')));
        setState(() => _busy = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (draft.isEmpty) return;

    final choice = await showDialog<_ReviewChoice>(
      context: context,
      builder: (_) => _AiReviewDialog(
        draft: draft,
        hasExisting: widget.target.text.trim().isNotEmpty,
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice.action) {
      case _ReviewAction.replace:
        widget.target.text = choice.text;
      case _ReviewAction.append:
        final cur = widget.target.text.trimRight();
        widget.target.text = cur.isEmpty ? choice.text : '$cur\n${choice.text}';
      case _ReviewAction.discard:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = context.watch<SettingsProvider>().hasApiKey;
    if (!hasKey) return const SizedBox.shrink();

    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: _busy ? null : _run,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: KColors.surface2,
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: KColors.phosphor))
              else
                const Icon(Icons.auto_awesome,
                    size: 12, color: KColors.phosphor),
              const SizedBox(width: 4),
              Text(_busy ? 'Drafting…' : 'AI draft',
                  style: const TextStyle(
                      color: KColors.phosphor, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label row for a field that offers an AI draft: the section label on
/// the left, the button on the right. Keeps the button out of the text
/// field itself so multi-line boxes stay clean.
class AiAssistedLabel extends StatelessWidget {
  final String label;
  final TextEditingController target;
  final Future<RaidAssistPrompt> Function() buildPrompt;
  final String tooltip;

  const AiAssistedLabel({
    super.key,
    required this.label,
    required this.target,
    required this.buildPrompt,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2)),
      ),
      AiAssistButton(
          target: target, buildPrompt: buildPrompt, tooltip: tooltip),
    ]);
  }
}

enum _ReviewAction { replace, append, discard }

class _ReviewChoice {
  final _ReviewAction action;
  final String text;
  const _ReviewChoice(this.action, this.text);
}

class _AiReviewDialog extends StatefulWidget {
  final String draft;
  final bool hasExisting;
  const _AiReviewDialog({required this.draft, required this.hasExisting});

  @override
  State<_AiReviewDialog> createState() => _AiReviewDialogState();
}

class _AiReviewDialogState extends State<_AiReviewDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.draft);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Row(children: [
        Icon(Icons.auto_awesome, size: 14, color: KColors.phosphor),
        SizedBox(width: 8),
        Text('AI draft', style: TextStyle(color: KColors.text, fontSize: 15)),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit before using it. Nothing is saved until you save the '
              'item.',
              style: TextStyle(color: KColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              minLines: 5,
              maxLines: 14,
              style: const TextStyle(
                  color: KColors.text, fontSize: 12, height: 1.5),
              decoration: const InputDecoration(isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop(const _ReviewChoice(_ReviewAction.discard, '')),
          child: const Text('Discard',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        if (widget.hasExisting)
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(_ReviewChoice(_ReviewAction.append, _ctrl.text.trim())),
            child: const Text('Append', style: TextStyle(fontSize: 12)),
          ),
        ElevatedButton(
          onPressed: () => Navigator.of(context)
              .pop(_ReviewChoice(_ReviewAction.replace, _ctrl.text.trim())),
          child: Text(widget.hasExisting ? 'Replace' : 'Use draft',
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

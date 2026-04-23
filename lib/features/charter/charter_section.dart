import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

/// Read-only section with heading divider + prose text.
class CharterSection extends StatelessWidget {
  final String label;
  final String? value;
  final String? subLabel;
  final String? subValue;

  const CharterSection({
    super.key,
    required this.label,
    this.value,
    this.subLabel,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = (value != null && value!.isNotEmpty) ||
        (subValue != null && subValue!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: label),
        const SizedBox(height: 8),
        if (!hasContent)
          const Text(
            '—',
            style: TextStyle(color: KColors.textMuted, fontSize: 13),
          )
        else ...[
          if (value != null && value!.isNotEmpty)
            _ProseText(value!),
          if (subLabel != null &&
              subValue != null &&
              subValue!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              subLabel!,
              style: const TextStyle(
                color: KColors.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 4),
            _ProseText(subValue!),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(height: 1, color: KColors.border),
        ),
      ],
    );
  }
}

class _ProseText extends StatelessWidget {
  final String text;
  const _ProseText(this.text);

  @override
  Widget build(BuildContext context) {
    // Simple markdown-lite: split on newlines, render bullet lines specially
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ') || trimmed.startsWith('• ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ',
                    style: TextStyle(color: KColors.textDim, fontSize: 13)),
                Expanded(
                  child: Text(
                    trimmed.substring(2),
                    style: const TextStyle(
                        color: KColors.text, fontSize: 13, height: 1.6),
                  ),
                ),
              ],
            ),
          );
        }
        if (trimmed.isEmpty) return const SizedBox(height: 6);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            trimmed,
            style: const TextStyle(
                color: KColors.text, fontSize: 13, height: 1.6),
          ),
        );
      }).toList(),
    );
  }
}

/// Editable version of a charter section — TextFormField with label.
class CharterEditSection extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int minLines;

  const CharterEditSection({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.minLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          style: const TextStyle(
              color: KColors.text, fontSize: 13, height: 1.6),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: KColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: KColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: KColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: KColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: KColors.amber),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

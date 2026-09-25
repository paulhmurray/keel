import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// The "big pop-up" item view introduced for plan activities, lifted into
/// one shared frame so Actions and RAID dialogs get the same geometry:
/// two columns when the window is wide enough, a single scrolling
/// column otherwise, and a footer row inside the body.
///
/// The accent bar in the title follows the register's colour so the
/// dialog reads as belonging to the tab it was opened from.
bool detailTwoColumns(BuildContext context) =>
    MediaQuery.of(context).size.width >= 1280;

class DetailDialog extends StatelessWidget {
  final Color accent;

  /// Title row content — usually a ref chip, the kind label and any
  /// trailing controls (Convert menu, etc.).
  final List<Widget> title;
  final List<Widget> left;
  final List<Widget> right;

  /// Footer buttons, laid out in a Row. Put a `Spacer()` before the
  /// right-aligned ones.
  final List<Widget> footer;
  final GlobalKey<FormState>? formKey;

  const DetailDialog({
    super.key,
    required this.accent,
    required this.title,
    required this.left,
    required this.right,
    required this.footer,
    this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    final twoCol = detailTwoColumns(context);
    final size = MediaQuery.of(context).size;

    Widget body;
    if (twoCol) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: left)),
              const SizedBox(width: 28),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: right)),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: footer),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...left,
          ...right,
          const SizedBox(height: 16),
          Row(children: footer),
        ],
      );
    }

    Widget content = SingleChildScrollView(child: body);
    if (formKey != null) content = Form(key: formKey, child: content);

    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Row(children: [
        Container(
            width: 3,
            height: 20,
            color: accent,
            margin: const EdgeInsets.only(right: 10)),
        ...title,
      ]),
      content: SizedBox(
        width: twoCol ? min(1180, size.width * 0.92) : min(760, size.width * 0.9),
        height: min(940, size.height * 0.88),
        child: content,
      ),
    );
  }
}

/// Amber ref chip ("R4", "AC12") for dialog titles.
class DetailRefChip extends StatelessWidget {
  final String text;
  const DetailRefChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: KColors.amberDim,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: const TextStyle(
              color: KColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Dialog title text, sized to match the plan activity dialog.
class DetailTitle extends StatelessWidget {
  final String text;
  const DetailTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: KColors.text, fontSize: 16));
}

/// Uppercase micro-label used to head a section inside the dialog.
class DetailSectionLabel extends StatelessWidget {
  final String text;
  const DetailSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: KColors.textDim,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      );
}

/// Read-mode field: label above wrapped value. Hidden when empty, so
/// callers can list every field and let the blanks drop out.
class DetailField extends StatelessWidget {
  final String label;
  final String? value;
  final bool large;
  final Color? valueColor;

  const DetailField(this.label, this.value,
      {super.key, this.large = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            v,
            style: TextStyle(
              color: valueColor ?? KColors.text,
              fontSize: large ? 14 : 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin divider with breathing room, for separating dialog sections.
class DetailDivider extends StatelessWidget {
  const DetailDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(color: KColors.border, height: 1),
      );
}

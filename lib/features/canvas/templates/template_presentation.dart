import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/keel_colors.dart';

/// Opens a full-screen overlay for a template view (currently the User
/// Story Map is the only one that supports this). The overlay sits
/// above the entire shell, hiding nav rail / left panel / right Claude
/// panel without needing per-shell coordination.
///
/// ESC or the exit button closes it. The same widget tree behind the
/// overlay continues to render, so when the user exits they land back
/// where they were with no state lost.
Future<void> openTemplatePresentation(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Widget child,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: KColors.bg,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) =>
        _PresentationScaffold(title: title, icon: icon, child: child),
    transitionBuilder: (_, anim, __, c) {
      return FadeTransition(opacity: anim, child: c);
    },
  );
}

class _PresentationScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PresentationScaffold({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: KColors.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: const BoxDecoration(
                  color: KColors.surface,
                  border: Border(
                    bottom: BorderSide(color: KColors.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: KColors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'PRESENTATION',
                      style: TextStyle(
                        color: KColors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.fullscreen_exit, size: 14),
                      label: const Text('Exit (Esc)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KColors.amber,
                        side: const BorderSide(color: KColors.amber),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                        minimumSize: const Size(0, 30),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

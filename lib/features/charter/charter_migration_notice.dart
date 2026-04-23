import 'package:flutter/material.dart';
import '../../shared/theme/keel_colors.dart';

class CharterMigrationNotice extends StatelessWidget {
  final VoidCallback onOpenCharter;
  final VoidCallback onDismiss;

  const CharterMigrationNotice({
    super.key,
    required this.onOpenCharter,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text(
        'Programme Overview has been redesigned',
        style: TextStyle(color: KColors.text, fontSize: 14),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Vision, Scope, and Team content has moved to the new '
              'Charter section in the nav rail. Your Team notes were preserved '
              'as Delivery Approach — you can reorganise them into other '
              'sections if needed.',
              style: TextStyle(
                  color: KColors.textDim, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),
            Row(children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenCharter();
                },
                child: const Text('Open Charter'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onDismiss();
                },
                child: const Text('Dismiss',
                    style: TextStyle(
                        color: KColors.textDim, fontSize: 12)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

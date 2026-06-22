import 'package:flutter/material.dart';

import '../theme/keel_colors.dart';

/// Prompts for the sync encryption password. Returns the entered string,
/// or null if the user cancels (or submits empty). Shared by the Settings
/// page and the header "Sync needed" quick-sync button so both use one
/// dialog.
Future<String?> showSyncPasswordDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _SyncPasswordDialog(),
  );
}

/// Stateful so the controller's lifecycle is tied to the dialog widget —
/// disposing it here (not right after [showDialog] resolves) avoids
/// "controller used after dispose" during the dialog's exit animation.
class _SyncPasswordDialog extends StatefulWidget {
  const _SyncPasswordDialog();

  @override
  State<_SyncPasswordDialog> createState() => _SyncPasswordDialogState();
}

class _SyncPasswordDialogState extends State<_SyncPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Sync Password',
          style: TextStyle(color: KColors.text, fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your sync password to encrypt/decrypt data.\n'
            'This can be the same as your account password.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Sync password',
              hintText: 'Enter encryption password',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim)),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

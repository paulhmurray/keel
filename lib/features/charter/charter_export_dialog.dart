import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../../core/charter/charter_exporter.dart';
import '../../shared/theme/keel_colors.dart';

class CharterExportDialog extends StatefulWidget {
  final String projectName;
  final ProjectCharter charter;

  const CharterExportDialog({
    super.key,
    required this.projectName,
    required this.charter,
  });

  @override
  State<CharterExportDialog> createState() => _CharterExportDialogState();
}

class _CharterExportDialogState extends State<CharterExportDialog> {
  bool _exporting = false;
  String? _result;
  String? _error;

  Future<void> _export(String format) async {
    setState(() { _exporting = true; _error = null; _result = null; });
    try {
      final path = await CharterExporter.export(
        projectName: widget.projectName,
        charter: widget.charter,
        format: format,
      );
      setState(() => _result = path);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Export Charter',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export the programme charter as a standalone document.',
              style: TextStyle(color: KColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_result != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KColors.phosDim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_result!,
                    style: const TextStyle(
                        color: KColors.phosphor, fontSize: 11)),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: KColors.redDim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        color: KColors.red, fontSize: 11)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(
                onPressed: _exporting ? null : () => _export('html'),
                icon: _exporting
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.html, size: 16),
                label: Text(_exporting ? 'Exporting…' : 'HTML'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _exporting ? null : () => _export('md'),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Markdown'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.surface2,
                  foregroundColor: KColors.text,
                  side: const BorderSide(color: KColors.border2),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close',
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

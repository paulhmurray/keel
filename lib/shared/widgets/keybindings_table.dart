import 'package:flutter/material.dart';
import '../theme/keel_colors.dart';

class KeybindingsTable extends StatelessWidget {
  const KeybindingsTable({super.key});

  static const _bindings = [
    ('Open Journal (new entry)', 'Ctrl+j'),
    ('Open Journal (history)', 'Ctrl+Shift+j'),
    ('Save journal entry', 'Ctrl+Enter'),
    ('Open Inbox', 'Ctrl+i'),
    ('Toggle Claude panel', 'Ctrl+Shift+c'),
    ('Accept inbox item', 'y  (in inbox)'),
    ('Reject inbox item', 'n  (in inbox)'),
    ('Navigate inbox', '↑ / ↓  (in inbox)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _bindings
          .map(
            (b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(b.$1,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 12)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KColors.surface2,
                      border: Border.all(color: KColors.border2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      b.$2,
                      style: const TextStyle(
                        color: KColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

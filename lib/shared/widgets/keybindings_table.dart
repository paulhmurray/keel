import 'package:flutter/material.dart';
import '../theme/keel_colors.dart';

class KeybindingsTable extends StatelessWidget {
  const KeybindingsTable({super.key});

  static const _bindings = [
    ('Leader key (Spacebar)', 'SPC'),
    ('  → Programme overview', 'SPC SPC'),
    ('  → Timeline', 'SPC t'),
    ('  → RAID › Risks', 'SPC r r'),
    ('  → RAID › Risks › New', 'SPC r r n'),
    ('  → RAID › Assumptions', 'SPC r a'),
    ('  → RAID › Assumptions › New', 'SPC r a n'),
    ('  → RAID › Issues', 'SPC r i'),
    ('  → RAID › Issues › New', 'SPC r i n'),
    ('  → RAID › Dependencies', 'SPC r d'),
    ('  → RAID › Dependencies › New', 'SPC r d n'),
    ('  → Decisions', 'SPC d'),
    ('  → Decisions › New', 'SPC d n'),
    ('  → People', 'SPC p'),
    ('  → Actions', 'SPC a'),
    ('  → Inbox', 'SPC i'),
    ('  → Context › Entries', 'SPC c e'),
    ('  → Context › Entries › New', 'SPC c e n'),
    ('  → Context › Documents', 'SPC c d'),
    ('  → Context › Documents › Upload', 'SPC c d n'),
    ('  → Context › Glossary', 'SPC c g'),
    ('  → Context › Glossary › New term', 'SPC c g n'),
    ('  → Reports', 'SPC R'),
    ('  → Journal', 'SPC j'),
    ('  → Playbook', 'SPC P'),
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

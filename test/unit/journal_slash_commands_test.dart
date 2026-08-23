import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/journal/journal_slash_menu.dart';

void main() {
  test('command names are unique', () {
    final names = kSlashCommands.map((c) => c.command).toList();
    expect(names.toSet().length, names.length);
  });

  test('/day is offered and filterable', () {
    expect(
        filteredSlashCommands('day').map((c) => c.command), contains('/day'));
  });

  test('/day template has the dated header and all four sections', () {
    final day =
        kSlashCommands.firstWhere((c) => c.command == '/day').template;
    expect(day, startsWith('## {{today}}'));
    expect(day, contains('**Top 3 today**'));
    expect(day, contains('1. ⟨'));
    expect(day, contains('2. ⟨'));
    expect(day, contains('3. ⟨'));
    expect(day, contains('**On my radar**'));
    expect(day, contains('**End of day**'));
    expect(day, contains('Moved: '));
    expect(day, contains('Didn\'t move: '));
    expect(day, contains('Carrying to tomorrow: '));
    expect(day, contains('Escalations sent: '));
  });
}

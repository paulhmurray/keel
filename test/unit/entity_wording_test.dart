import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/context/programme_context.dart';
import 'package:keel/core/context/programme_context_service.dart';
import 'package:keel/core/database/database.dart';

/// A project must never be called a programme in what we hand the LLM.
void main() {
  ProgrammeContext ctx({required bool isProgramme}) => ProgrammeContext(
        projectId: 'p',
        projectName: 'TAC Integration',
        programmeRag: 'amber',
        isProgramme: isProgramme,
        assembledAt: DateTime(2026, 9, 27),
      );

  test('a project prompt says PROJECT and reserves "programme" for the parent',
      () {
    final s = ProgrammeContextService(AppDatabase.memory())
        .toPromptString(ctx(isProgramme: false));
    expect(s, startsWith('PROJECT CONTEXT'));
    expect(s, contains('Refer to it as "the project"'));
    expect(s, contains('"programme" means only the wider programme'));
    expect(s, contains('Project: TAC Integration'));
    expect(s, contains('Overall RAG: AMBER'));
    expect(s, isNot(contains('Programme RAG')));
  });

  test('a programme prompt says PROGRAMME', () {
    final s = ProgrammeContextService(AppDatabase.memory())
        .toPromptString(ctx(isProgramme: true));
    expect(s, startsWith('PROGRAMME CONTEXT'));
    expect(s, contains('Refer to it as "the programme"'));
    expect(s, contains('Programme: TAC Integration'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/llm/charter_assist_prompts.dart';

void main() {
  test('a project charter never calls itself a programme', () {
    final p = charterAssistPrompt(
      field: CharterField.vision,
      isProgramme: false,
      objectives: '- Retire the legacy adapter',
      vision: 'Old draft',
    );
    expect(p.system, contains('Call it "the project"'));
    expect(p.system, contains('"programme" means only the wider programme'));
    expect(p.user, contains('Objectives:\n- Retire the legacy adapter'));
    expect(p.user, contains('Vision (existing draft, to improve):\nOld draft'));
    expect(p.user, contains('Write the VISION'));
    expect(p.user, contains('for the project'));
  });

  test('a programme charter says programme; other sections are context', () {
    final p = charterAssistPrompt(
      field: CharterField.assumptions,
      isProgramme: true,
      keyConstraints: '- Hard stop 30 June',
      projectContext: 'CTX',
    );
    expect(p.system, startsWith('CTX'));
    expect(p.system, contains('Call it "the programme"'));
    expect(p.user, contains('Key constraints:\n- Hard stop 30 June'));
    expect(p.user, isNot(contains('Assumptions:\n')));
    expect(p.user, contains('We are assuming [statement] because'));
  });

  test('every field has a label and an instruction', () {
    for (final f in CharterField.values) {
      expect(charterFieldLabel(f), isNotEmpty);
      final p = charterAssistPrompt(field: f, isProgramme: false);
      expect(p.user, contains(charterFieldLabel(f).toUpperCase().split(' ').first));
    }
  });
}

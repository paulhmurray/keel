import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/wardley_map/wardley_map_model.dart';

void main() {
  test('encode → decode round-trips components and dependencies', () {
    const content = WardleyMapContent(
      components: [
        WardleyComponent(
            id: 'u', name: 'User', positionX: 0.9, positionY: 0.05),
        WardleyComponent(
            id: 'w', name: 'Website', positionX: 0.6, positionY: 0.4,
            notes: 'custom built'),
      ],
      dependencies: [
        WardleyDependency(id: 'd1', fromComponentId: 'u', toComponentId: 'w'),
      ],
    );

    final decoded = WardleyMapContent.decode(content.encode());
    expect(decoded.components, hasLength(2));
    final user = decoded.components.firstWhere((c) => c.id == 'u');
    expect(user.name, 'User');
    expect(user.positionX, 0.9);
    expect(user.positionY, 0.05);
    final web = decoded.components.firstWhere((c) => c.id == 'w');
    expect(web.notes, 'custom built');
    expect(decoded.dependencies.single.fromComponentId, 'u');
    expect(decoded.dependencies.single.toComponentId, 'w');
  });

  test('decode tolerates junk / empty and yields an empty map', () {
    expect(WardleyMapContent.decode(null).components, isEmpty);
    expect(WardleyMapContent.decode('').components, isEmpty);
    expect(WardleyMapContent.decode('not json {{').dependencies, isEmpty);
    // Missing keys default cleanly.
    expect(WardleyMapContent.decode('{}').components, isEmpty);
  });

  test('positions clamp to 0..1 on copyWith and decode', () {
    const c = WardleyComponent(id: 'x', name: 'X');
    expect(c.copyWith(positionX: 1.8).positionX, 1.0);
    expect(c.copyWith(positionY: -0.5).positionY, 0.0);
    final decoded = WardleyMapContent.decode(
        '{"components":[{"id":"x","name":"X","position_x":5,"position_y":-2}]}');
    expect(decoded.components.single.positionX, 1.0);
    expect(decoded.components.single.positionY, 0.0);
  });

  test('copyWith notes: keep vs clear', () {
    const c = WardleyComponent(id: 'x', name: 'X', notes: 'keep me');
    expect(c.copyWith(name: 'Y').notes, 'keep me'); // untouched
    expect(c.copyWith(notes: null).notes, isNull); // explicitly cleared
  });
}

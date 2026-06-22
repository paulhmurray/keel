import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/user_story_map/usm_model.dart';

void main() {
  group('UsmContent JSON', () {
    test('round-trips activities (with nested tasks), releases, stories',
        () {
      const original = UsmContent(
        activities: [
          UsmActivity(id: 'a1', name: 'Discover', tasks: [
            UsmTask(id: 't1', name: 'Search destinations'),
          ]),
        ],
        releases: [
          UsmRelease(id: 'r1', name: 'MVP'),
        ],
        stories: [
          UsmStory(
            id: 's1',
            taskId: 't1',
            releaseId: 'r1',
            title: 'Search by city',
            description: 'Single-text-input search',
            estimate: 'M',
            tags: ['search', 'frontend'],
            acceptanceCriteria: [
              'Results within 2 seconds',
              'Empty state for no results',
            ],
          ),
        ],
      );
      final back = UsmContent.decode(original.encode());
      expect(back.activities.single.name, 'Discover');
      expect(back.activities.single.tasks.single.name,
          'Search destinations');
      expect(back.releases.single.name, 'MVP');
      expect(back.stories.single.title, 'Search by city');
      expect(back.stories.single.tags, ['search', 'frontend']);
      expect(back.stories.single.acceptanceCriteria, hasLength(2));
    });

    test('decode tolerates null / empty / malformed / wrong-shape', () {
      expect(UsmContent.decode(null).activities, isEmpty);
      expect(UsmContent.decode('').stories, isEmpty);
      expect(UsmContent.decode('not-json').releases, isEmpty);
      expect(UsmContent.decode('[1,2,3]').activities, isEmpty);
    });

    test('activities, tasks within each activity, and releases all sort '
        'by sortOrder on decode', () {
      const c = UsmContent(
        activities: [
          UsmActivity(id: 'a', name: 'a', sortOrder: 2, tasks: [
            UsmTask(id: 'ta2', name: 'late', sortOrder: 2),
            UsmTask(id: 'ta0', name: 'early', sortOrder: 0),
          ]),
          UsmActivity(id: 'b', name: 'b', sortOrder: 0),
          UsmActivity(id: 'c', name: 'c', sortOrder: 1),
        ],
        releases: [
          UsmRelease(id: 'r2', name: 'late', sortOrder: 1),
          UsmRelease(id: 'r1', name: 'early', sortOrder: 0),
        ],
      );
      final back = UsmContent.decode(c.encode());
      expect(back.activities.map((x) => x.id), ['b', 'c', 'a']);
      expect(back.activities[2].tasks.map((t) => t.id),
          ['ta0', 'ta2']);
      expect(back.releases.map((r) => r.id), ['r1', 'r2']);
    });

    test('story optional fields are omitted from JSON when empty/null',
        () {
      const c = UsmContent(stories: [
        UsmStory(id: 's1', taskId: 't', releaseId: 'r', title: 'minimal'),
      ]);
      final raw = c.encode();
      // No description, estimate, tags, or acceptance criteria keys for
      // a bare story.
      expect(raw.contains('"description"'), isFalse);
      expect(raw.contains('"estimate"'), isFalse);
      expect(raw.contains('"tags"'), isFalse);
      expect(raw.contains('"acceptance_criteria"'), isFalse);
    });
  });

  group('UsmContent helpers', () {
    test('allTasks flattens in render order', () {
      const c = UsmContent(activities: [
        UsmActivity(id: 'a1', name: 'a1', tasks: [
          UsmTask(id: 't1a'),
          UsmTask(id: 't1b', sortOrder: 1),
        ]),
        UsmActivity(id: 'a2', name: 'a2', sortOrder: 1, tasks: [
          UsmTask(id: 't2a'),
        ]),
      ]);
      expect(c.allTasks.map((t) => t.id), ['t1a', 't1b', 't2a']);
    });

    test('storiesAt filters by both axes', () {
      const c = UsmContent(stories: [
        UsmStory(id: 's1', taskId: 't1', releaseId: 'r1', title: 'x'),
        UsmStory(id: 's2', taskId: 't1', releaseId: 'r2', title: 'y'),
        UsmStory(id: 's3', taskId: 't2', releaseId: 'r1', title: 'z'),
      ]);
      expect(c.storiesAt('t1', 'r1').map((s) => s.id), ['s1']);
      expect(c.storiesAt('t1', 'r2').map((s) => s.id), ['s2']);
      expect(c.storiesAt('t2', 'r2'), isEmpty);
    });
  });

  group('UsmStory.copyWith', () {
    test('moving across cells preserves story content', () {
      const a = UsmStory(
        id: 's1',
        taskId: 't1',
        releaseId: 'r1',
        title: 'kept',
        description: 'kept too',
        estimate: 'M',
        tags: ['x'],
        acceptanceCriteria: ['must do'],
      );
      final b = a.copyWith(taskId: 't2', releaseId: 'r2');
      expect(b.taskId, 't2');
      expect(b.releaseId, 'r2');
      expect(b.title, 'kept');
      expect(b.description, 'kept too');
      expect(b.estimate, 'M');
      expect(b.tags, ['x']);
      expect(b.acceptanceCriteria, ['must do']);
    });

    test('description / estimate sentinel: explicit null clears', () {
      const a = UsmStory(
        id: 's',
        taskId: 't',
        releaseId: 'r',
        description: 'kept',
        estimate: '3 days',
      );
      expect(a.copyWith(title: 'u').description, 'kept');
      expect(a.copyWith(description: null).description, isNull);
      expect(a.copyWith(estimate: null).estimate, isNull);
    });
  });
}

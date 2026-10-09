import 'package:flutter_test/flutter_test.dart';
import 'package:set_notes/logbook.dart';

void main() {
  test(
    'restart recovers edits, stable IDs, active workout and rest deadline',
    () {
      final b = Logbook();
      final w = b.start();
      final e = ExerciseLog(name: 'Squat', rest: 120);
      w.exercises.add(e);
      final s = SetEntry(kg: 60, reps: 8, note: 'controlled');
      e.sets.add(s);
      final now = DateTime.utc(2026, 10, 9);
      expect(b.complete(e, s, now), isTrue);
      expect(b.complete(e, s, now), isFalse);
      final restored = Logbook.decode(b.encode());
      expect(restored.active!.id, w.id);
      expect(restored.active!.exercises.single.sets.single.id, s.id);
      expect(restored.remaining(now.add(const Duration(seconds: 30))), 90);
      expect(restored.remaining(now.add(const Duration(seconds: 200))), 0);
      expect(restored.active!.completed, 1);
    },
  );
  test('completed volume excludes warmups, uncompleted and bodyweight', () {
    final w = Workout(
      exercises: [
        ExerciseLog(
          name: 'Squat',
          sets: [
            SetEntry(kg: 60, reps: 8, done: true),
            SetEntry(kg: 20, reps: 10, done: true, warmup: true),
            SetEntry(kg: 100, reps: 20),
          ],
        ),
        ExerciseLog(
          name: 'Push-up',
          bodyweight: true,
          sets: [SetEntry(reps: 20, done: true)],
        ),
      ],
    );
    expect(w.volumeKg, 480);
    expect(w.completed, 3);
  });
  test('unit conversion does not reinterpret stored weights', () {
    expect(toKg(fromKg(60, 'lb'), 'lb'), closeTo(60, 0.000001));
    final b = Logbook();
    b.start().exercises.add(
      ExerciseLog(name: 'Row', sets: [SetEntry(kg: 60, reps: 8)]),
    );
    b.unit = 'lb';
    expect(
      Logbook.decode(b.encode()).active!.exercises.single.sets.single.kg,
      60,
    );
  });
  test('routine has new identities and unchecked copied sets', () {
    final w = Workout(
      exercises: [
        ExerciseLog(name: 'Row', sets: [SetEntry(kg: 20, reps: 8, done: true)]),
      ],
    );
    final r = w.template('Pull');
    expect(r.id, isNot(w.id));
    expect(r.completed, 0);
    expect(r.exercises.single.sets.single.kg, 20);
    final b = Logbook()
      ..workouts = [w]
      ..routines = [r];
    expect(() => Logbook.decode(b.encode()), returnsNormally);
  });
  test(
    'offline finish, previous suggestion and historical edits roundtrip',
    () {
      final b = Logbook();
      final w = b.start();
      final e = ExerciseLog(
        name: 'Row',
        sets: [SetEntry(kg: 20, reps: 8, done: true)],
      );
      w.exercises.add(e);
      w.finished = true;
      expect(b.previous('row')!.kg, 20);
      final n = b.start();
      expect(n.id, isNot(w.id));
      w.exercises.single.sets.single.reps = 9;
      expect(
        Logbook.decode(b.encode())
            .workouts
            .last
            .exercises
            .single
            .sets
            .single
            .reps,
        9,
      );
    },
  );
  test('invalid backup and duplicate IDs rejected before replacement', () {
    expect(() => Logbook.decode('{"schema":9}'), throwsA(anything));
    final b = Logbook();
    final w = b.start();
    b.workouts.add(w);
    expect(() => Logbook.decode(b.encode()), throwsFormatException);
    expect(
      () => SetEntry.fromJson({
        'id': 's',
        'kg': -1,
        'reps': 8,
        'warmup': false,
        'done': false,
        'note': '',
      }),
      throwsFormatException,
    );
  });
  test('invalid blank set cannot count completed or start timer', () {
    final b = Logbook();
    final e = ExerciseLog(name: 'Row');
    final s = SetEntry();
    expect(() => b.complete(e, s, DateTime.now()), throwsFormatException);
    expect(s.done, false);
    expect(b.restUntil, null);
  });
}

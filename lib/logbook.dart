import 'dart:convert';
import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
double toKg(double value, String unit) =>
    unit == 'lb' ? value * 0.45359237 : value;
double fromKg(double value, String unit) =>
    unit == 'lb' ? value / 0.45359237 : value;

class SetEntry {
  SetEntry({
    String? id,
    this.kg = 0,
    this.reps = 0,
    this.warmup = false,
    this.done = false,
    this.note = '',
  }) : id = id ?? newId();
  final String id;
  double kg;
  int reps;
  bool warmup, done;
  String note;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kg': kg,
    'reps': reps,
    'warmup': warmup,
    'done': done,
    'note': note,
  };
  factory SetEntry.fromJson(Map<String, dynamic> j) {
    final kg = (j['kg'] as num).toDouble(), reps = j['reps'] as int;
    if (!kg.isFinite || kg < 0 || kg > 10000 || reps < 0 || reps > 10000) {
      throw const FormatException('Invalid set');
    }
    return SetEntry(
      id: j['id'] as String,
      kg: kg,
      reps: reps,
      warmup: j['warmup'] as bool,
      done: j['done'] as bool,
      note: j['note'] as String,
    );
  }
}

class ExerciseLog {
  ExerciseLog({
    String? id,
    required this.name,
    this.bodyweight = false,
    this.rest = 90,
    List<SetEntry>? sets,
  }) : id = id ?? newId(),
       sets = sets ?? [];
  final String id;
  String name;
  bool bodyweight;
  int rest;
  List<SetEntry> sets;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bodyweight': bodyweight,
    'rest': rest,
    'sets': sets.map((e) => e.toJson()).toList(),
  };
  factory ExerciseLog.fromJson(Map<String, dynamic> j) {
    final rest = j['rest'] as int, name = j['name'] as String;
    if (rest < 0 || rest > 3600 || name.trim().isEmpty || name.length > 120) {
      throw const FormatException('Invalid exercise');
    }
    return ExerciseLog(
      id: j['id'] as String,
      name: name,
      bodyweight: j['bodyweight'] as bool,
      rest: rest,
      sets: (j['sets'] as List)
          .map((e) => SetEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class Workout {
  Workout({
    String? id,
    DateTime? date,
    this.title = 'Workout',
    this.note = '',
    this.finished = false,
    List<ExerciseLog>? exercises,
  }) : id = id ?? newId(),
       date = date ?? DateTime.now(),
       exercises = exercises ?? [];
  final String id;
  DateTime date;
  String title, note;
  bool finished;
  List<ExerciseLog> exercises;
  int get completed =>
      exercises.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);
  double get volumeKg => exercises
      .where((e) => !e.bodyweight)
      .fold(
        0,
        (n, e) =>
            n +
            e.sets
                .where((s) => s.done && !s.warmup)
                .fold<double>(0, (v, s) => v + s.kg * s.reps),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'title': title,
    'note': note,
    'finished': finished,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };
  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
    id: j['id'] as String,
    date: DateTime.parse(j['date'] as String),
    title: j['title'] as String,
    note: j['note'] as String,
    finished: j['finished'] as bool,
    exercises: (j['exercises'] as List)
        .map((e) => ExerciseLog.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
  Workout template(String name) => Workout(
    title: name,
    exercises: exercises
        .map(
          (e) => ExerciseLog(
            name: e.name,
            bodyweight: e.bodyweight,
            rest: e.rest,
            sets: e.sets
                .map((s) => SetEntry(kg: s.kg, reps: s.reps, warmup: s.warmup))
                .toList(),
          ),
        )
        .toList(),
  );
}

class Logbook {
  String unit = 'kg';
  bool autoRest = true;
  List<Workout> workouts = [], routines = [];
  DateTime? restUntil;
  String? restExercise;
  Workout? get active => workouts.where((w) => !w.finished).firstOrNull;
  Workout start([Workout? routine]) {
    if (active != null) return active!;
    final w = routine?.template(routine.title) ?? Workout();
    workouts.insert(0, w);
    return w;
  }

  bool complete(ExerciseLog e, SetEntry s, DateTime now) {
    if (s.done) return false;
    if (s.reps <= 0 || (!e.bodyweight && s.kg <= 0)) {
      throw const FormatException('Enter valid weight and repetitions');
    }
    s.done = true;
    if (autoRest && e.rest > 0) {
      restUntil = now.add(Duration(seconds: e.rest));
      restExercise = e.name;
    }
    return true;
  }

  int remaining(DateTime now) => restUntil == null
      ? 0
      : max(0, (restUntil!.difference(now).inMilliseconds / 1000).ceil());
  SetEntry? previous(String name) {
    for (final w in workouts.where((w) => w.finished)) {
      for (final e in w.exercises.where(
        (e) => e.name.toLowerCase() == name.toLowerCase(),
      )) {
        for (final s in e.sets.reversed) {
          if (s.done) return s;
        }
      }
    }
    return null;
  }

  String encode() => jsonEncode({
    'schema': 1,
    'unit': unit,
    'autoRest': autoRest,
    'workouts': workouts.map((w) => w.toJson()).toList(),
    'routines': routines.map((w) => w.toJson()).toList(),
    'restUntil': restUntil?.toIso8601String(),
    'restExercise': restExercise,
  });
  static Logbook decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['schema'] != 1 || !['kg', 'lb'].contains(j['unit'])) {
      throw const FormatException('Unsupported backup');
    }
    final b = Logbook()
      ..unit = j['unit'] as String
      ..autoRest = j['autoRest'] as bool;
    b.workouts = (j['workouts'] as List)
        .map((w) => Workout.fromJson(Map<String, dynamic>.from(w)))
        .toList();
    b.routines = (j['routines'] as List)
        .map((w) => Workout.fromJson(Map<String, dynamic>.from(w)))
        .toList();
    b.restUntil = j['restUntil'] == null
        ? null
        : DateTime.parse(j['restUntil'] as String);
    b.restExercise = j['restExercise'] as String?;
    final ids = <String>{};
    for (final w in [...b.workouts, ...b.routines]) {
      for (final id in [
        w.id,
        ...w.exercises.expand((e) => [e.id, ...e.sets.map((s) => s.id)]),
      ]) {
        if (id.isEmpty || !ids.add(id)) {
          throw const FormatException('Duplicate identity');
        }
      }
    }
    if (b.workouts.where((w) => !w.finished).length > 1) {
      throw const FormatException('Multiple active workouts');
    }
    return b;
  }
}

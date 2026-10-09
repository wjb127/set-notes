import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'logbook.dart';
import 'strings.dart';
import 'ads.dart';

Future<void> start() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Logbook book;
  bool recovery = false;
  try {
    book = Logbook.decode(prefs.getString('notebook') ?? Logbook().encode());
  } catch (_) {
    book = Logbook();
    recovery = true;
  }
  runApp(SetNotes(book: book, prefs: prefs, recovery: recovery));
}

class SetNotes extends StatefulWidget {
  const SetNotes({
    super.key,
    required this.book,
    required this.prefs,
    this.recovery = false,
    this.initializeAds = true,
  });
  final Logbook book;
  final SharedPreferences prefs;
  final bool recovery;
  final bool initializeAds;
  @override
  State<SetNotes> createState() => _SetNotesState();
}

class _SetNotesState extends State<SetNotes> {
  late Logbook book = widget.book;
  final ads = AdsController();
  Future<void> writes = Future.value();
  Timer? ticker;
  Workout? viewed;
  int page = 0;
  bool saving = false, saveFailed = false;
  late bool recovery = widget.recovery;
  @override
  void initState() {
    super.initState();
    if (widget.initializeAds) ads.initialize();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && book.restUntil != null) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    ads.dispose();
    super.dispose();
  }

  Future<void> save() {
    if (recovery) return Future.value();
    final snapshot = book.encode();
    setState(() => saving = true);
    writes = writes
        .catchError((_) {})
        .then((_) async {
          try {
            if (!await widget.prefs.setString('notebook', snapshot)) {
              throw StateError(L.t0);
            }
            if (mounted) setState(() => saveFailed = false);
          } catch (_) {
            if (mounted) setState(() => saveFailed = true);
          }
        })
        .whenComplete(() {
          if (mounted) setState(() => saving = false);
        });
    return writes;
  }

  void change(void Function() action) {
    setState(action);
    save();
  }

  void message(BuildContext c, String text) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
  String number(num n) => NumberFormat('0.##').format(n);
  String date(DateTime d) => DateFormat.yMMMd().add_jm().format(d.toLocal());
  Future<String?> textPrompt(BuildContext c, String title, String value) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text(L.t1),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text(L.t2),
          ),
        ],
      ),
    );
    return result;
  }

  Widget action(String title, VoidCallback run, {IconData? icon}) =>
      FilledButton.icon(
        onPressed: run,
        icon: Icon(icon ?? Icons.add),
        label: Text(title),
      );
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: S.title,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff285b52)),
      scaffoldBackgroundColor: const Color(0xfff5f4ee),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    ),
    home: Builder(
      builder: (c) {
        final w = viewed ?? book.active;
        return PopScope(
          canPop: viewed == null,
          onPopInvokedWithResult: (did, _) {
            if (!did) setState(() => viewed = null);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(viewed == null ? S.title : viewed!.title),
              leading: viewed == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => viewed = null),
                    ),
              actions: [
                IconButton(
                  tooltip: S.settings,
                  onPressed: () {
                    setState(() {
                      viewed = null;
                      page = 3;
                    });
                  },
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (recovery)
                    MaterialBanner(
                      content: const Text(L.t3),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => page = 3),
                          child: const Text(L.t4),
                        ),
                      ],
                    ),
                  if (saveFailed)
                    MaterialBanner(
                      content: const Text(S.saveError),
                      actions: [
                        TextButton(onPressed: save, child: const Text(L.t5)),
                      ],
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: viewed != null || (page == 0 && w != null)
                          ? workout(c, w!)
                          : page == 1
                          ? history(c)
                          : page == 2
                          ? routines(c)
                          : page == 3
                          ? settings(c)
                          : home(c),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: viewed != null
                ? null
                : NavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: (i) => setState(() => page = i),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.fitness_center),
                        label: L.t6,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.history),
                        label: S.history,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bookmarks_outlined),
                        label: S.routines,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        label: L.t4,
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
  List<Widget> home(BuildContext c) => [
    const Text(
      S.tagline,
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 12),
    const Text(L.t7),
    const SizedBox(height: 24),
    action(S.start, () {
      if (!recovery) change(() => book.start());
    }, icon: Icons.play_arrow),
    const SizedBox(height: 24),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${book.workouts.where((w) => w.finished).length} saved workouts',
              style: const TextStyle(fontSize: 22),
            ),
            const Text(L.t8),
          ],
        ),
      ),
    ),
    SetupBanner(ads: ads),
  ];
  List<Widget> workout(BuildContext c, Workout w) => [
    Row(
      children: [
        Expanded(
          child: Text(
            w.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: L.t9,
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final t = await textPrompt(c, L.t10, w.title);
            if (t != null && t.isNotEmpty) change(() => w.title = t);
          },
        ),
      ],
    ),
    TextButton.icon(
      icon: const Icon(Icons.calendar_today),
      label: Text(date(w.date)),
      onPressed: () async {
        final d = await showDatePicker(
          context: c,
          initialDate: w.date.toLocal(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (d != null) {
          change(
            () => w.date = DateTime(
              d.year,
              d.month,
              d.day,
              w.date.hour,
              w.date.minute,
            ),
          );
        }
      },
    ),
    Text(
      saving
          ? L.t11
          : saveFailed
          ? L.t12
          : L.t13,
      style: TextStyle(color: saveFailed ? Colors.red : Colors.teal),
    ),
    Text(
      '${w.completed} completed sets · ${number(fromKg(w.volumeKg, book.unit))} ${book.unit} volume',
    ),
    const SizedBox(height: 12),
    if (!w.finished && book.restUntil != null)
      Card(
        color: const Color(0xffe1ece5),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${book.restExercise ?? 'Rest'}\n${book.remaining(DateTime.now())} seconds left',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              TextButton(
                onPressed: () => change(() {
                  book.restUntil = null;
                  book.restExercise = null;
                }),
                child: const Text(L.t14),
              ),
            ],
          ),
        ),
      ),
    ...w.exercises.map((e) => exercise(c, w, e)),
    action(L.t15, () => addExercise(c, w)),
    const SizedBox(height: 12),
    TextFormField(
      key: ValueKey('note-${w.id}'),
      initialValue: w.note,
      maxLines: 2,
      maxLength: 2000,
      decoration: const InputDecoration(labelText: L.t16),
      onChanged: (v) => change(() => w.note = v),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      icon: const Icon(Icons.bookmark_add_outlined),
      label: const Text(L.t17),
      onPressed: () async {
        final t = await textPrompt(c, L.t18, w.title);
        if (t != null && t.isNotEmpty) {
          change(() => book.routines.add(w.template(t)));
        }
      },
    ),
    if (!w.finished)
      FilledButton.icon(
        icon: const Icon(Icons.check),
        label: const Text(L.t19),
        onPressed: () async {
          if (w.completed == 0) {
            message(c, L.t20);
            return;
          }
          change(() {
            w.finished = true;
            book.restUntil = null;
            viewed = null;
            page = 1;
          });
          await writes;
        },
      ),
    const Padding(
      padding: EdgeInsets.only(top: 16),
      child: Text(S.volume, style: TextStyle(fontSize: 12)),
    ),
  ];
  Widget exercise(BuildContext c, Workout w, ExerciseLog e) {
    final p = book.previous(e.name);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text(L.t21),
                  selected: e.bodyweight,
                  onSelected: (v) => change(() => e.bodyweight = v),
                ),
                TextButton(
                  onPressed: () async {
                    final t = await textPrompt(c, L.t22, '${e.rest}');
                    final v = int.tryParse(t ?? '');
                    if (v != null && v >= 0 && v <= 3600) {
                      change(() => e.rest = v);
                    }
                  },
                  child: Text('Rest ${e.rest}s'),
                ),
              ],
            ),
            if (p != null)
              Text(
                'Previous completed set: ${number(fromKg(p.kg, book.unit))} ${book.unit} × ${p.reps} (suggestion only)',
                style: const TextStyle(fontSize: 12),
              ),
            ...e.sets.asMap().entries.map(
              (row) => setRow(c, e, row.value, row.key + 1, w.finished),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text(L.t23),
                    onPressed: () => change(() => e.sets.add(SetEntry())),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final s = e.sets.lastOrNull ?? p;
                      change(
                        () => e.sets.add(
                          SetEntry(
                            kg: s?.kg ?? 0,
                            reps: s?.reps ?? 0,
                            warmup: s?.warmup ?? false,
                          ),
                        ),
                      );
                    },
                    child: const Text(L.t24),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget setRow(
    BuildContext c,
    ExerciseLog e,
    SetEntry s,
    int index,
    bool historical,
  ) => Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: s.done ? Colors.teal : Colors.black12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Text('#$index'),
            const SizedBox(width: 10),
            if (!e.bodyweight)
              Expanded(
                child: TextFormField(
                  key: ValueKey('${s.id}-${book.unit}'),
                  initialValue: s.kg == 0
                      ? ''
                      : number(fromKg(s.kg, book.unit)),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: book.unit),
                  onChanged: (v) {
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    change(() {
                      s.kg = (n != null && n.isFinite && n >= 0 && n <= 10000)
                          ? toKg(n, book.unit)
                          : 0;
                      if (s.kg == 0) s.done = false;
                    });
                  },
                ),
              ),
            if (!e.bodyweight) const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: ValueKey('${s.id}-reps'),
                initialValue: s.reps == 0 ? '' : '${s.reps}',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: L.t25),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  change(() {
                    s.reps = (n != null && n >= 0 && n <= 10000) ? n : 0;
                    if (s.reps == 0) s.done = false;
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            FilterChip(
              label: const Text(L.t26),
              selected: s.warmup,
              onSelected: (v) => change(() => s.warmup = v),
            ),
            const Spacer(),
            IconButton(
              tooltip: L.t27,
              onPressed: () {
                final i = e.sets.indexOf(s);
                change(() => e.sets.remove(s));
                ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(
                    content: const Text(L.t28),
                    action: SnackBarAction(
                      label: L.t29,
                      onPressed: () => change(
                        () => e.sets.insert(i.clamp(0, e.sets.length), s),
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        TextFormField(
          key: ValueKey('${s.id}-note'),
          initialValue: s.note,
          maxLength: 500,
          decoration: const InputDecoration(labelText: L.t30),
          onChanged: (v) => change(() => s.note = v),
        ),
        SizedBox(
          width: double.infinity,
          child: s.done
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text(L.t31),
                  onPressed: () => change(() => s.done = false),
                )
              : FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text(L.t32),
                  onPressed: () {
                    try {
                      change(() {
                        if (historical) {
                          if (s.reps <= 0 || (!e.bodyweight && s.kg <= 0)) {
                            throw const FormatException();
                          }
                          s.done = true;
                        } else {
                          book.complete(e, s, DateTime.now());
                        }
                      });
                    } catch (_) {
                      message(c, L.t33);
                    }
                  },
                ),
        ),
      ],
    ),
  );
  Future<void> addExercise(BuildContext c, Workout w) async {
    String query = '';
    const presets = [
      L.t34,
      'Squat',
      'Deadlift',
      L.t35,
      L.t36,
      'Pull-up',
      'Push-up',
      'Lunge',
      L.t37,
      L.t38,
      L.t39,
      'Plank',
    ];
    final name = await showDialog<String>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text(L.t40),
          content: SizedBox(
            width: 400,
            height: 350,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: L.t41),
                  maxLength: 120,
                  onChanged: (v) => set(() => query = v.trim()),
                ),
                Expanded(
                  child: ListView(
                    children: presets
                        .where(
                          (p) => p.toLowerCase().contains(query.toLowerCase()),
                        )
                        .map(
                          (p) => ListTile(
                            title: Text(p),
                            onTap: () => Navigator.pop(c, p),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text(L.t1),
            ),
            FilledButton(
              onPressed: query.isEmpty ? null : () => Navigator.pop(c, query),
              child: const Text(L.t42),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty) {
      change(
        () => w.exercises.add(
          ExerciseLog(
            name: name,
            bodyweight: ['Pull-up', 'Push-up', 'Plank'].contains(name),
            sets: [SetEntry()],
          ),
        ),
      );
    }
  }

  List<Widget> history(BuildContext c) => [
    const Text(
      L.t43,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    ),
    if (book.workouts.where((w) => w.finished).isEmpty)
      const Padding(padding: EdgeInsets.all(24), child: Text(L.t44)),
    ...book.workouts
        .where((w) => w.finished)
        .map(
          (w) => Card(
            child: ListTile(
              title: Text(w.title),
              subtitle: Text(
                '${date(w.date)}\n${w.completed} sets · ${number(fromKg(w.volumeKg, book.unit))} ${book.unit}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => viewed = w),
            ),
          ),
        ),
    const SizedBox(height: 16),
    const Text(L.t45, style: TextStyle(fontSize: 22)),
    ...{
      for (final w in book.workouts.where((w) => w.finished))
        for (final e in w.exercises) e.name,
    }.map(
      (name) => ExpansionTile(
        title: Text(name),
        children: [
          for (final w in book.workouts.where((w) => w.finished))
            for (final e in w.exercises.where((e) => e.name == name))
              ListTile(
                title: Text(date(w.date)),
                subtitle: Text(
                  e.sets
                      .where((s) => s.done)
                      .map(
                        (s) =>
                            '${e.bodyweight ? L.t21 : '${number(fromKg(s.kg, book.unit))} ${book.unit}'} × ${s.reps}${s.warmup ? ' warmup' : ''}',
                      )
                      .join(' · '),
                ),
              ),
        ],
      ),
    ),
    if (book.active == null) SetupBanner(ads: ads),
  ];
  List<Widget> routines(BuildContext c) => [
    const Text(
      L.t46,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    ),
    const Text(L.t47),
    ...book.routines.map(
      (r) => Card(
        child: ListTile(
          title: Text(r.title),
          subtitle: Text('${r.exercises.length} exercises'),
          trailing: IconButton(
            tooltip: L.t48,
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              final i = book.routines.indexOf(r);
              change(() => book.routines.remove(r));
              ScaffoldMessenger.of(c).showSnackBar(
                SnackBar(
                  content: const Text(L.t49),
                  action: SnackBarAction(
                    label: L.t29,
                    onPressed: () => change(
                      () => book.routines.insert(
                        i.clamp(0, book.routines.length),
                        r,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          onTap: () {
            if (recovery) return;
            if (book.active != null) {
              message(c, L.t50);
              return;
            }
            change(() {
              book.start(r);
              page = 0;
            });
          },
        ),
      ),
    ),
  ];
  List<Widget> settings(BuildContext c) => [
    const Text(
      S.settings,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    ),
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'kg', label: Text('kg')),
        ButtonSegment(value: 'lb', label: Text('lb')),
      ],
      selected: {book.unit},
      onSelectionChanged: (s) => change(() => book.unit = s.first),
    ),
    const Text(L.t51),
    SwitchListTile(
      title: const Text(L.t52),
      value: book.autoRest,
      onChanged: (v) => change(() => book.autoRest = v),
    ),
    const Text(S.backup),
    OutlinedButton.icon(
      icon: const Icon(Icons.ios_share),
      label: const Text(L.t53),
      onPressed: () async {
        await writes;
        if (!c.mounted) return;
        final text = recovery
            ? widget.prefs.getString('notebook') ?? ''
            : book.encode();
        try {
          final box = c.findRenderObject() as RenderBox?;
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  Uint8List.fromList(utf8.encode(text)),
                  mimeType: 'application/json',
                  name: 'set-notes-backup.json',
                ),
              ],
              fileNameOverrides: ['set-notes-backup.json'],
              sharePositionOrigin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            ),
          );
        } catch (_) {
          if (c.mounted) {
            message(c, L.t54);
          }
        }
      },
    ),
    OutlinedButton.icon(
      icon: const Icon(Icons.restore),
      label: const Text(L.t55),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: c,
          builder: (c) => AlertDialog(
            title: const Text(L.t56),
            content: const Text(S.restore),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text(L.t1),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text(L.t57),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          final f = await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: L.t58,
                extensions: ['json'],
                uniformTypeIdentifiers: ['public.json'],
                mimeTypes: ['application/json'],
              ),
            ],
          );
          if (f == null || !c.mounted) return;
          if (await f.length() > 5000000) throw const FormatException();
          final restored = Logbook.decode(await f.readAsString());
          change(() {
            recovery = false;
            book = restored;
            viewed = null;
          });
          await writes;
          if (c.mounted) {
            message(c, saveFailed ? S.saveError : L.t59);
          }
        } catch (_) {
          if (c.mounted) {
            message(c, L.t60);
          }
        }
      },
    ),
    const Divider(),
    const Text(S.privacy),
    TextButton(
      onPressed: () => launchUrl(
        Uri.parse('https://wjb127.github.io/set-notes/privacy.html'),
        mode: LaunchMode.externalApplication,
      ),
      child: const Text(L.t61),
    ),
    ListenableBuilder(
      listenable: ads,
      builder: (_, _) => ads.privacyRequired
          ? TextButton(onPressed: ads.privacyOptions, child: const Text(L.t62))
          : const SizedBox.shrink(),
    ),
    const Text(L.t63),
  ];
}

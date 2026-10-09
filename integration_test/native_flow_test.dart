import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:set_notes/app.dart';
import 'package:set_notes/logbook.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native offline workout and persisted recovery', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notebook');
    final b = Logbook();
    final last = Workout(
      title: 'Pull day',
      date: DateTime.now().subtract(const Duration(days: 2)),
      finished: true,
      exercises: [
        ExerciseLog(
          name: 'Barbell row',
          sets: [
            SetEntry(kg: 40, reps: 10, done: true),
            SetEntry(kg: 45, reps: 8, done: true),
          ],
        ),
      ],
    );
    b.workouts.add(last);
    await t.pumpWidget(SetNotes(book: b, prefs: prefs, initializeAds: false));
    await t.pumpAndSettle();
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    await t.tap(find.text('Start workout'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add exercise'));
    await t.pumpAndSettle();
    await t.tap(find.text('Squat'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), '60');
    await t.enterText(find.byType(TextFormField).at(1), '8');
    await t.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Complete set'));
    await t.pumpAndSettle();
    await t.tap(find.text('Complete set'));
    await t.pump();
    final recovered = Logbook.decode(prefs.getString('notebook')!);
    expect(recovered.active!.completed, 1);
    expect(recovered.active!.volumeKg, 480);
    expect(recovered.remaining(DateTime.now()), greaterThan(0));
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      SetNotes(book: recovered, prefs: prefs, initializeAds: false),
    );
    await t.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await t.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('01-workout-en');
    await t.scrollUntilVisible(
      find.text('Finish workout'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Finish workout'));
    await t.pumpAndSettle();
    expect(Logbook.decode(prefs.getString('notebook')!).active, isNull);
    await binding.takeScreenshot('02-history-en');
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('lb'));
    await t.pumpAndSettle();
    expect(Logbook.decode(prefs.getString('notebook')!).unit, 'lb');
    expect(
      Logbook.decode(prefs.getString('notebook')!)
          .workouts
          .first
          .exercises
          .single
          .sets
          .single
          .kg,
      60,
    );
    await binding.takeScreenshot('03-backup-en');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}

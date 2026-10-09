import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:set_notes/app.dart';
import 'package:set_notes/logbook.dart';

void main() {
  testWidgets('offline start, custom exercise, autosave and active recovery', (
    t,
  ) async {
    t.view.physicalSize = const Size(900, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    await t.pumpWidget(
      SetNotes(book: Logbook(), prefs: p, initializeAds: false),
    );
    await t.tap(find.text('Start workout'));
    await t.pump();
    await t.tap(find.text('Add exercise'));
    await t.pumpAndSettle();
    await t.tap(find.text('Squat'));
    await t.pumpAndSettle();
    expect(find.text('Complete set'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), '60');
    await t.enterText(fields.at(1), '8');
    await t.pump();
    await t.ensureVisible(find.text('Complete set'));
    await t.pumpAndSettle();
    await t.tap(find.text('Complete set'));
    await t.pump();
    expect(Logbook.decode(p.getString('notebook')!).active!.completed, 1);
    final recovered = Logbook.decode(p.getString('notebook')!);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      SetNotes(book: recovered, prefs: p, initializeAds: false),
    );
    await t.pump();
    expect(find.text('Squat'), findsOneWidget);
    expect(find.textContaining('1 completed sets'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('corrupt storage is preserved and start is gated', (t) async {
    SharedPreferences.setMockInitialValues({'notebook': 'corrupt'});
    final p = await SharedPreferences.getInstance();
    await t.pumpWidget(
      SetNotes(book: Logbook(), prefs: p, recovery: true, initializeAds: false),
    );
    await t.tap(find.text('Start workout'));
    await t.pump();
    expect(p.getString('notebook'), 'corrupt');
    await t.pumpWidget(const SizedBox());
  });
}

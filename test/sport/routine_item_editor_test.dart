import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/routines/routine_item_editor_sheet.dart';
import 'package:insulink/src/sport/sport_models.dart';
import 'package:insulink/src/sport/sport_store.dart';
import 'package:insulink/src/sport/sport_sync.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

import '../support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TrainingState buildState() {
    const exercise = SportExercise(
      id: 'e1',
      name: 'Squat',
      kind: ExerciseKind.reps,
    );
    const routine = SportRoutine(
      id: 'r1',
      name: 'Legs',
      items: [
        RoutineItem(
          id: 'i1',
          exerciseId: 'e1',
          targetSets: 2,
          target: 7,
          restSeconds: 45,
        ),
      ],
    );
    return TrainingState(const SportStore(), [exercise], [routine], [], null);
  }

  Widget host(TrainingState state) =>
      ChangeNotifierProvider<TrainingState>.value(
        value: state,
        child: MaterialApp(
          localizationsDelegates: Locales.delegates,
          supportedLocales: Locales.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showRoutineItemEditorSheet(
                  context,
                  routineId: 'r1',
                  index: 0,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> editField(WidgetTester tester, String pill, String typed) async {
    await tester.tap(find.text(pill));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), typed);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('editing sets and reps via the text field updates the item', (
    tester,
  ) async {
    installSecureStorageMock();
    await Locales.init(['de', 'en']);
    final state = buildState();
    await tester.pumpWidget(host(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await editField(tester, '2', '9'); // sets pill shows "2"
    expect(state.routineById('r1')!.items.first.targetSets, 9);

    await editField(tester, '7', '11'); // reps pill shows "7"
    expect(state.routineById('r1')!.items.first.target, 11);

    // Persisting arms SportSync's 3s debounce; cancel it before the test ends so
    // it doesn't trip the "Timer still pending" invariant.
    SportSync.cancelPending();
  });
}

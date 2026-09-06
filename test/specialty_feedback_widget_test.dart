import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctordesk/widgets/specialty_feedback_widget.dart';

void main() {
  group('SpecialtyFeedbackRow widget tests', () {
    testWidgets('Submits thumbs up and locks out subsequent taps', (tester) async {
      int submitCount = 0;
      bool? lastLiked;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecialtyFeedbackRow(
              inputText: 'chest pain',
              matchedSpecialty: 'Cardiologist',
              source: 'rule_based',
              onSubmitFeedback: ({
                required String inputText,
                required String matchedSpecialty,
                required String source,
                required bool liked,
              }) async {
                submitCount++;
                lastLiked = liked;
              },
            ),
          ),
        ),
      );

      // Verify question and icons appear
      expect(find.text('Was this suggestion helpful?'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);

      // Tap thumbs up
      await tester.tap(find.byIcon(Icons.thumb_up_outlined));
      await tester.pump();

      // Verify feedback submitted once with liked = true
      expect(submitCount, 1);
      expect(lastLiked, isTrue);

      // Confirm confirmation message and that icons are gone
      expect(find.text('Thanks for confirming!'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
      expect(find.byIcon(Icons.thumb_down_outlined), findsNothing);
    });

    testWidgets('Failed/offline network callback does not crash or show error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpecialtyFeedbackRow(
              inputText: 'skin rash',
              matchedSpecialty: 'Dermatologist',
              source: 'rule_based',
              onSubmitFeedback: ({
                required String inputText,
                required String matchedSpecialty,
                required String source,
                required bool liked,
              }) async {
                // Simulating offline network exception
                throw Exception('SocketException: Failed to connect to server');
              },
            ),
          ),
        ),
      );

      // Tap thumbs down
      await tester.tap(find.byIcon(Icons.thumb_down_outlined));
      await tester.pump();

      // UI state transitions gracefully without unhandled exception
      expect(find.text("Thanks — we'll improve this."), findsOneWidget);
    });
  });
}

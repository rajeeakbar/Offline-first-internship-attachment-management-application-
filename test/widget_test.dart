import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internship_app/main.dart';

void main() {
  testWidgets('App builds and starts', (WidgetTester tester) async {
    // Build our app and trigger a frame.

    await tester.pumpWidget(
      const ProviderScope(
        child: InternshipApp(),
      ),
    );

    await tester.pumpWidget(const InternshipApp());

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();


    // Verify that the app is built.
    expect(find.byType(InternshipApp), findsOneWidget);
  });
}

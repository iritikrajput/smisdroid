import 'package:flutter_test/flutter_test.dart';
import 'package:smisdroid/main.dart';

void main() {
  testWidgets('SMISDroid app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const SMISDroidApp());
    await tester.pumpAndSettle();

    // Verify the app name is displayed
    expect(find.text('SMISDroid'), findsOneWidget);
  });
}

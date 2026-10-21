import 'package:flutter_test/flutter_test.dart';
import 'package:standard_2800_v5/main.dart';

void main() {
  testWidgets('Standard 2800-V5 app launches',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SeismoApp());

    expect(find.text('Standard 2800-V5'), findsOneWidget);
  });
}

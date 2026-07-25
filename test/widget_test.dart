import 'package:flutter_test/flutter_test.dart';
import 'package:thanhdthaichink/main.dart';

void main() {
  testWidgets('Nailify app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NailifyApp());
    expect(find.byType(NailifyApp), findsOneWidget);
  });
}

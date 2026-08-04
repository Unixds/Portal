import 'package:flutter_test/flutter_test.dart';
import 'package:portal/main.dart';

void main() {
  testWidgets('Portal app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PortalApp());
  });
}

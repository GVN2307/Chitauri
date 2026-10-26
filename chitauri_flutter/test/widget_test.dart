import 'package:flutter_test/flutter_test.dart';
import 'package:chitauri_flutter/main.dart';

void main() {
  testWidgets('Chitauri app sanity test', (WidgetTester tester) async {
    // Basic instantiation check
    expect(const ChitauriApp(), isNotNull);
  });
}

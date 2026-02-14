import 'package:flutter_test/flutter_test.dart';

import 'package:liga_zala/main.dart';

void main() {
  testWidgets('MyApp renders auth entry screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Лига Зала'), findsOneWidget);
    expect(find.text('Войти / Регистрация'), findsOneWidget);
  });
}

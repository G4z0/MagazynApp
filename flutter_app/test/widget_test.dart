import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:magazyn_app/l10n/translations.dart';
import 'package:magazyn_app/main.dart';

void main() {
  testWidgets('shows login screen when there is no saved session',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await initTranslations();

    await tester.pumpWidget(const MagazynApp());
    await tester.pumpAndSettle();

    expect(find.text(tr('LOGIN_TITLE')), findsOneWidget);
    expect(find.text(tr('BUTTON_SIGN_IN')), findsOneWidget);
  });
}

// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:child_tracker/main.dart';
import 'package:child_tracker/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectLoginScreenForLocale(
    WidgetTester tester,
    Locale locale,
  ) async {
    final l10n = await AppLocalizations.delegate.load(locale);
    SharedPreferences.setMockInitialValues({
      'app_locale': locale.languageCode,
    });

    await tester.pumpWidget(const MyApp());
    expect(find.text(l10n.appTitle), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text(l10n.signIn), findsOneWidget);
    expect(find.text(l10n.password), findsOneWidget);
  }

  testWidgets('App boots to login when no stored session exists in English', (
    WidgetTester tester,
  ) async {
    await expectLoginScreenForLocale(tester, const Locale('en'));
  });

  testWidgets('App boots to login when no stored session exists in Pashto', (
    WidgetTester tester,
  ) async {
    await expectLoginScreenForLocale(tester, const Locale('ps'));
  });

  testWidgets('App boots to login when no stored session exists in Dari', (
    WidgetTester tester,
  ) async {
    await expectLoginScreenForLocale(tester, const Locale('fa'));
  });
}

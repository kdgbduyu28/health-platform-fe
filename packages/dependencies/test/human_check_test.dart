import 'package:api_sdk/api_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Outside a browser there is no Turnstile, so the check must stay out of
  // the way: no token, nothing drawn, and the form still submits.
  test('is off without a browser, even with a site key', () async {
    final check = HumanCheckController(siteKey: '1x00000000000000000000AA');
    expect(check.enabled, isFalse);
    expect(await check.token(), isNull);
    check.reset(); // no widget yet: must not throw
    check.dispose();
  });

  test('is off without a site key', () {
    final check = HumanCheckController(siteKey: '');
    expect(check.enabled, isFalse);
    check.dispose();
  });

  testWidgets('draws nothing when off', (tester) async {
    final check = HumanCheckController(siteKey: '');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HumanCheck(controller: check, action: 'sign-in')),
    ));
    expect(find.byType(HtmlElementView), findsNothing);
    check.dispose();
  });

  test('explains a refused captcha', () {
    expect(
      describeError(const AuthException(
        'captcha protection: request disallowed (timeout-or-duplicate)',
        statusCode: '400',
        code: 'captcha_failed',
      )),
      contains('security check'),
    );
  });
}

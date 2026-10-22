// The web page around the app: settings an iPhone home-screen app needs.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('index.html keeps the app out of the notch and home-indicator areas', () {
    final html = File('web/index.html').readAsStringSync();
    // Flutter web doesn't pad for iOS safe areas: drawing under them offsets touches
    expect(html, isNot(contains('viewport-fit=cover')));
    expect(html, isNot(contains('black-translucent')));
    expect(html, contains('name="viewport"'));
  });
}

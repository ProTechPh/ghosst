import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/theme.dart';

void main() {
  test('Android keeps the stable zoom page transition', () {
    // Flutter 3.47's predictive-back transition crashed on pop; the theme
    // must not fall back to it.
    final builder =
        AppTheme.dark.pageTransitionsTheme.builders[TargetPlatform.android];
    expect(builder, isA<ZoomPageTransitionsBuilder>());
  });
}

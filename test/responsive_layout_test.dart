import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultsync_client/core/utils/responsive_layout.dart';

void main() {
  testWidgets('ResponsiveLayout should detect mobile', (tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1.0;

    bool isMobile = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          isMobile = ResponsiveLayout.isMobile(context);
          return const SizedBox();
        }),
      ),
    );

    expect(isMobile, isTrue);
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('ResponsiveLayout should detect desktop', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;

    bool isDesktop = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          isDesktop = ResponsiveLayout.isDesktop(context);
          return const SizedBox();
        }),
      ),
    );

    expect(isDesktop, isTrue);
    addTearDown(tester.view.resetPhysicalSize);
  });
}

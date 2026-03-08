import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultsync_client/features/auth/presentation/recovery_screen.dart';

void main() {
  testWidgets('RecoveryScreen should have email input', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RecoveryScreen(),
        ),
      ),
    );

    expect(find.byType(TextField), findsAtLeastNWidgets(1));
    expect(find.text('Email'), findsOneWidget);
  });
}

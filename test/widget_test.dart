import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bike_nav/main.dart';

void main() {
  testWidgets('shows account options on launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BikeNavApp());
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsAtLeastNWidgets(1));
    expect(find.text('Create account'), findsAtLeastNWidgets(1));
  });

  testWidgets('restores a signed-in rider to the map', (tester) async {
    SharedPreferences.setMockInitialValues({
      'bike_nav_current_user': 'rider@example.com',
    });

    await tester.pumpWidget(const BikeNavApp());
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('rider'), findsOneWidget);
    expect(find.byTooltip('Plan bike route'), findsOneWidget);
  });

  testWidgets('opens and saves the rider bike profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.saveAccount(
      const Account(
        fullName: 'Test Rider',
        email: 'rider@example.com',
        password: 'secure123',
        bikeProfile: BikeProfile(
          name: 'City bike',
          type: 'City / commuter',
          isElectric: false,
        ),
      ),
    );
    tester.view.physicalSize = const Size(780, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: MapScreen(userEmail: 'rider@example.com')),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bike profile'));
    await tester.pumpAndSettle();

    expect(find.byType(BikeProfileScreen), findsOneWidget);
    expect(find.text('City / commuter'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Updated city bike');
    await tester.tap(find.text('Save bike profile'));
    await tester.pumpAndSettle();

    final account = await AuthService.findAccount('rider@example.com');
    expect(account?.bikeProfile?.name, 'Updated city bike');
  });

  testWidgets('shows route search controls', (tester) async {
    tester.view.physicalSize = const Size(780, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: MapScreen(userEmail: 'rider@example.com')),
    );
    await tester.pump();

    expect(find.text('BikeNav'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byTooltip('Plan bike route'), findsOneWidget);
    expect(find.text('No trains'), findsOneWidget);
    expect(find.text('Boarding train station'), findsNothing);
    expect(find.text('Exit train station'), findsNothing);
  });
}

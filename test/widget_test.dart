// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bike_nav/main.dart';

void main() {
  testWidgets('shows the account creation option on launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BikeNavApp());
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('restores a saved session to the map after reload', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bike_nav_current_user': 'rider@example.com',
    });

    await tester.pumpWidget(const BikeNavApp());
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('rider'), findsOneWidget);
  });

  test('saves accounts for later sign-in', () async {
    SharedPreferences.setMockInitialValues({});
    const account = Account(
      fullName: 'Test Rider',
      email: 'rider@example.com',
      password: 'secure123',
    );

    await AuthService.saveAccount(account);
    final accounts = await AuthService.loadAccounts();

    expect(accounts, hasLength(1));
    expect(accounts.single.email, account.email);
    expect(accounts.single.password, account.password);
  });

  test('saves bike profiles to the matching account', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.saveAccount(
      const Account(
        fullName: 'First Rider',
        email: 'first@example.com',
        password: 'secure123',
      ),
    );
    await AuthService.saveAccount(
      const Account(
        fullName: 'Second Rider',
        email: 'second@example.com',
        password: 'secure456',
      ),
    );

    const profile = BikeProfile(
      name: 'Blue Comet',
      type: 'Road',
      isElectric: true,
      electricClass: 2,
    );
    await AuthService.saveBikeProfile('FIRST@example.com', profile);

    final firstAccount = await AuthService.findAccount('first@example.com');
    final secondAccount = await AuthService.findAccount('second@example.com');
    expect(firstAccount?.bikeProfile?.name, 'Blue Comet');
    expect(firstAccount?.bikeProfile?.electricClass, 2);
    expect(secondAccount?.bikeProfile, isNull);
  });

  testWidgets('opens the saved bike profile from the account menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.saveAccount(
      const Account(
        fullName: 'Test Rider',
        email: 'rider@example.com',
        password: 'secure123',
        bikeProfile: BikeProfile(
          name: 'Blue Comet',
          type: 'Road',
          isElectric: true,
          electricClass: 2,
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
    expect(find.text('Blue Comet'), findsOneWidget);
    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Class 2'), findsOneWidget);
  });

  testWidgets('offers urban bike types and keeps saved legacy types', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.saveAccount(
      const Account(
        fullName: 'Test Rider',
        email: 'rider@example.com',
        password: 'secure123',
        bikeProfile: BikeProfile(
          name: 'Old bike',
          type: 'Mountain',
          isElectric: false,
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: BikeProfileScreen(userEmail: 'rider@example.com'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mountain'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('City / commuter'), findsOneWidget);
    expect(find.text('Folding'), findsOneWidget);
    expect(find.text('Cargo / utility'), findsOneWidget);
    expect(find.text('Mountain'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows route search controls on the map', (tester) async {
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
  });

  test('parses clear turn instructions and route estimates', () {
    final shape = encodePolyline([
      [51.5, -0.1],
      [51.51, -0.11],
    ], accuracyExponent: 6);
    final result = RouteService.parseValhallaResponse({
      'trip': {
        'summary': {'length': 2.3, 'time': 600, 'has_ferry': false},
        'legs': [
          {
            'shape': shape,
            'maneuvers': [
              {
                'instruction': 'Start on High Street',
                'length': 0.1,
                'begin_shape_index': 0,
              },
              {
                'instruction': 'Turn left onto Market Road',
                'length': 2.2,
                'begin_shape_index': 1,
                'end_shape_index': 1,
              },
              for (var index = 0; index < 5; index++)
                {
                  'instruction': 'Continue through junction $index',
                  'length': 0.1,
                  'begin_shape_index': 1,
                  'end_shape_index': 1,
                },
            ],
          },
        ],
      },
    });

    expect(result.directions[1].text, 'Turn left onto Market Road');
    expect(
      result.directions[1].beginLocation!.latitude,
      closeTo(51.51, 0.000001),
    );
    expect(
      result.directions[1].endLocation!.latitude,
      closeTo(51.51, 0.000001),
    );
    expect(result.directions, hasLength(7));
    expect(result.summary, '2.3 km · about 10 min');
    expect(result.distanceMeters, 2300);
  });

  test('parses train-station place suggestions', () {
    final suggestions = PlaceService.parseSuggestions({
      'features': [
        {
          'properties': {
            'name': 'Oxford Station',
            'city': 'Oxford',
            'country': 'United Kingdom',
            'osm_key': 'railway',
            'osm_value': 'station',
          },
          'geometry': {
            'coordinates': [-1.2702, 51.7537],
          },
        },
      ],
    });

    expect(suggestions, hasLength(1));
    expect(suggestions.single.label, 'Oxford Station');
    expect(suggestions.single.category, 'Train station');
    expect(suggestions.single.point.latitude, 51.7537);
  });

  test('biases place search to the supplied nearby location', () {
    final uri = PlaceService.searchUri(
      'Oxford station',
      near: const LatLng(51.7537, -1.2702),
    );

    expect(uri.queryParameters['lat'], '51.7537');
    expect(uri.queryParameters['lon'], '-1.2702');
    expect(uri.queryParameters['limit'], '8');
  });

  test('requests bicycle routing with ferries disabled', () {
    final request = RouteService.requestBody(
      start: const LatLng(40.631, -73.952),
      end: const LatLng(40.721, -74.047),
      avoidFerries: true,
    );

    expect(request['costing'], 'bicycle');
    expect((request['costing_options'] as Map)['bicycle']['use_ferry'], 0);
    expect(request.containsKey('alternatives'), isFalse);
  });

  test('refuses a response that still contains a ferry', () {
    expect(
      () => RouteService.parseValhallaResponse({
        'trip': {
          'summary': {'length': 2.3, 'time': 600, 'has_ferry': true},
          'legs': [
            {
              'shape': encodePolyline([
                [51.5, -0.1],
                [51.51, -0.11],
              ], accuracyExponent: 6),
              'maneuvers': const [],
            },
          ],
        },
      }, avoidFerries: true),
      throwsA(isA<Exception>()),
    );
  });
}

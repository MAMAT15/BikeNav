import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:bike_nav/main.dart';
import 'package:bike_nav/screens/route_preferences.dart';

Map<String, dynamic> bicycleOptions(
  RoutePreferences preferences, {
  bool avoidFerries = false,
}) {
  final body = RouteService.requestBody(
    start: const LatLng(40.631, -73.952),
    end: const LatLng(40.660, -73.969),
    avoidFerries: avoidFerries,
    preferences: preferences,
  );
  return (body['costing_options'] as Map<String, dynamic>)['bicycle']
      as Map<String, dynamic>;
}

void main() {
  test('no profile routes as a Hybrid at the default speed', () {
    expect(bicycleOptions(RoutePreferences.forBike()), {
      'bicycle_type': 'Hybrid',
    });
    expect(bicycleOptions(RoutePreferences.forBike(bikeType: 'Other')), {
      'bicycle_type': 'Hybrid',
    });
    expect(
      bicycleOptions(RoutePreferences.forBike(bikeType: 'City / commuter')),
      {'bicycle_type': 'Hybrid'},
    );
  });

  test('road bike routes as Road with no speed override', () {
    expect(bicycleOptions(RoutePreferences.forBike(bikeType: 'Road')), {
      'bicycle_type': 'Road',
    });
  });

  test('cargo and folding bikes ride slower', () {
    final cargo = bicycleOptions(
      RoutePreferences.forBike(bikeType: 'Cargo / utility'),
    );
    expect(cargo['bicycle_type'], 'Hybrid');
    expect(cargo['cycling_speed'], 15.0);

    final folding = bicycleOptions(
      RoutePreferences.forBike(bikeType: 'Folding'),
    );
    expect(folding['bicycle_type'], 'Hybrid');
    expect(folding['cycling_speed'], 16.0);
  });

  test('class 3 e-bike is faster and minds hills less', () {
    final options = bicycleOptions(
      RoutePreferences.forBike(
        bikeType: 'City / commuter',
        isElectric: true,
        electricClass: 3,
      ),
    );
    expect(options, {
      'bicycle_type': 'Hybrid',
      'cycling_speed': 28.0,
      'use_hills': 0.5,
    });
  });

  test('e-bike without a class uses the default e-bike speed', () {
    final options = bicycleOptions(
      RoutePreferences.forBike(bikeType: 'Road', isElectric: true),
    );
    expect(options['bicycle_type'], 'Road');
    expect(options['cycling_speed'], RoutePreferences.defaultElectricSpeedKph);
    expect(options['use_hills'], 0.5);
  });

  test('all route choices on', () {
    final options = bicycleOptions(
      RoutePreferences.forBike(
        bikeType: 'Hybrid',
        isElectric: true,
        electricClass: 1,
        avoidBusyRoads: true,
        avoidHills: true,
        shortest: true,
      ),
      avoidFerries: true,
    );
    expect(options, {
      'bicycle_type': 'Hybrid',
      'cycling_speed': 24.0,
      'use_roads': 0.0,
      // Avoid hills beats the e-bike setting.
      'use_hills': 0.0,
      'shortest': true,
      'use_ferry': 0,
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bike_nav/main.dart';
import 'package:bike_nav/screens/add_path.dart';
import 'package:bike_nav/screens/path_service.dart';

// A path exactly as the first Add Path version saved it.
const Map<String, dynamic> legacyPath = {
  'start': 'Park gate',
  'end': 'River trail',
  'startLatitude': 40.0,
  'startLongitude': -74.0,
  'endLatitude': 40.0,
  'endLongitude': -73.99,
  'description': 'Quiet cut-through',
  'status': 'Pending',
  'date': '2026-11-01 10:00:00.000000',
  'points': [
    {'latitude': 40.0, 'longitude': -74.0},
    {'latitude': 40.0, 'longitude': -73.995},
    {'latitude': 40.0, 'longitude': -73.99},
  ],
};

CommunityPath shortcut({String status = PathService.statusVerified}) {
  const points = [
    TrackPoint(point: LatLng(40.0, -73.998)),
    TrackPoint(point: LatLng(40.0, -73.99)),
    TrackPoint(point: LatLng(40.0, -73.982)),
  ];
  return CommunityPath(
    id: 'shortcut',
    submitter: 'rider@example.com',
    startName: 'West gate',
    endName: 'East gate',
    points: points,
    lengthMeters: PathService.trackLength(points.map((p) => p.point).toList()),
    durationSeconds: 200,
    date: '2026-11-01 10:00:00.000000',
    status: status,
  );
}

// Stands in for Valhalla: a straight line between the two locations,
// ridden at 4 m/s.
MockClient fakeValhalla(List<Map<String, dynamic>> requests) {
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add(body);
    final locations = body['locations'] as List<dynamic>;
    final from = LatLng(
      (locations[0]['lat'] as num).toDouble(),
      (locations[0]['lon'] as num).toDouble(),
    );
    final to = LatLng(
      (locations[1]['lat'] as num).toDouble(),
      (locations[1]['lon'] as num).toDouble(),
    );
    final meters = PathService.metersBetween(from, to);
    return http.Response(
      jsonEncode({
        'trip': {
          'summary': {'length': meters / 1000, 'time': meters / 4},
          'legs': [
            {
              'shape': encodePolyline([
                [from.latitude, from.longitude],
                [to.latitude, to.longitude],
              ], accuracyExponent: 6),
              'maneuvers': [
                {
                  'instruction': 'Bike east.',
                  'length': meters / 1000,
                  'begin_shape_index': 0,
                  'end_shape_index': 1,
                },
                {
                  'instruction': 'You have arrived at your destination.',
                  'length': 0,
                  'begin_shape_index': 1,
                  'end_shape_index': 1,
                },
              ],
            },
          ],
        },
      }),
      200,
    );
  });
}

void main() {
  const start = LatLng(40.0, -74.0);
  const end = LatLng(40.0, -73.98);

  test('loads a path saved before the new fields existed', () async {
    SharedPreferences.setMockInitialValues({
      'bike_nav_paths': jsonEncode([legacyPath]),
    });

    final paths = await PathService.loadPaths();

    expect(paths, hasLength(1));
    final path = paths.single;
    expect(path.id, 'legacy-2026-11-01 10:00:00.000000');
    expect(path.submitter, '');
    expect(path.startName, 'Park gate');
    expect(path.isPending, isTrue);
    expect(path.points, hasLength(3));
    expect(path.lengthMeters, closeTo(852, 5));
    expect(path.durationSeconds, 0);
    expect(path.confirmations, isEmpty);
  });

  test('saving keeps existing paths and their original fields', () async {
    SharedPreferences.setMockInitialValues({
      'bike_nav_paths': jsonEncode([legacyPath]),
    });

    await PathService.savePath(shortcut(status: PathService.statusPending));
    await PathService.confirmPath(
      'legacy-2026-11-01 10:00:00.000000',
      'a@example.com',
    );

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('bike_nav_paths')!) as List;
    expect(saved, hasLength(2));
    expect(saved[0]['startLatitude'], 40.0);
    expect(saved[0]['start'], 'Park gate');
    expect(saved[0]['confirmations'], ['a@example.com']);
    expect(saved[1]['id'], 'shortcut');
  });

  test('a path is verified after three other riders confirm it', () async {
    SharedPreferences.setMockInitialValues({});
    await PathService.savePath(shortcut(status: PathService.statusPending));

    // The submitter and repeat confirmations do not count.
    await PathService.confirmPath('shortcut', 'rider@example.com');
    await PathService.confirmPath('shortcut', 'a@example.com');
    await PathService.confirmPath('shortcut', 'A@example.com');
    var path = await PathService.confirmPath('shortcut', 'b@example.com');
    expect(path!.confirmations, ['a@example.com', 'b@example.com']);
    expect(path.isPending, isTrue);
    expect(await PathService.loadVerifiedPaths(), isEmpty);

    path = await PathService.confirmPath('shortcut', 'c@example.com');
    expect(path!.isVerified, isTrue);
    expect(await PathService.loadVerifiedPaths(), hasLength(1));
  });

  test('recording drops bad fixes and rejects short tracks', () {
    final time = DateTime(2026, 11, 1, 10);
    final first = TrackPoint(
      point: const LatLng(40.0, -74.0),
      time: time,
      accuracy: 5,
    );

    TrackPoint fix(double longitude, int seconds, double accuracy) {
      return TrackPoint(
        point: LatLng(40.0, longitude),
        time: time.add(Duration(seconds: seconds)),
        accuracy: accuracy,
      );
    }

    expect(PathService.shouldKeepFix(null, first), isTrue);
    // About 8.5 m in 2 s.
    expect(PathService.shouldKeepFix(first, fix(-73.9999, 2, 5)), isTrue);
    // Low accuracy.
    expect(PathService.shouldKeepFix(first, fix(-73.9999, 2, 80)), isFalse);
    // About 850 m in 2 s.
    expect(PathService.shouldKeepFix(first, fix(-73.99, 2, 5)), isFalse);

    expect(PathService.validateTrack(const []), isNotNull);
    expect(PathService.validateTrack([first]), isNotNull);

    final ride = [
      for (var index = 0; index < 20; index++)
        fix(-74.0 + index * 0.0001, index * 2, 5),
    ];
    expect(PathService.validateTrack(ride), isNull);
  });

  test('a recording must finish near the chosen destination', () {
    const destination = LatLng(40.0, -73.99);
    // About 43 m short of the destination.
    const near = [TrackPoint(point: LatLng(40.0, -73.9905))];
    // About 850 m short of the destination.
    const far = [TrackPoint(point: LatLng(40.0, -74.0))];

    expect(PathService.validateReachesEnd(near, destination), isNull);
    expect(PathService.validateReachesEnd(far, destination), isNotNull);
    expect(PathService.validateReachesEnd(const [], destination), isNotNull);
  });

  testWidgets('submit is disabled until a route is recorded and stopped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddPathScreen(userEmail: 'rider@example.com')),
    );

    final submit = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Path'),
    );
    expect(submit.onPressed, isNull);
    expect(
      find.text('Record a route and stop recording to submit it.'),
      findsOneWidget,
    );
  });

  test('skips paths that are a long way off the trip', () {
    final candidates = PathService.candidatesFor(
      start: start,
      end: end,
      baselineMeters: PathService.metersBetween(start, end),
      paths: [shortcut()],
    );

    // Only the west-to-east direction fits this trip.
    expect(candidates, hasLength(1));
    expect(candidates.single.reversed, isFalse);

    final farAway = PathService.candidatesFor(
      start: const LatLng(41.0, -74.0),
      end: const LatLng(41.0, -73.98),
      baselineMeters: 1700,
      paths: [shortcut()],
    );
    expect(farAway, isEmpty);
  });

  test('routes via a verified community path when it is faster', () async {
    final requests = <Map<String, dynamic>>[];

    final route = await http.runWithClient(
      () => RouteService.planBikeRoute(
        start: start,
        end: end,
        communityPaths: [shortcut()],
      ),
      () => fakeValhalla(requests),
    );

    // Baseline, start to path entry, path exit to end.
    expect(requests, hasLength(3));
    expect(route.summary, contains('via community path'));
    expect(route.durationSeconds, closeTo(285, 5));
    expect(route.directions.map((step) => step.text).toList(), [
      'Bike east.',
      'Follow community path: West gate to East gate',
      'Bike east.',
      'You have arrived at your destination.',
    ]);
    expect(route.points.first, start);
    expect(route.points.last, end);
    expect(route.points, contains(const LatLng(40.0, -73.99)));
  });

  test('keeps the normal route when no verified path helps', () async {
    final requests = <Map<String, dynamic>>[];

    final pendingOnly = await http.runWithClient(
      () => RouteService.planBikeRoute(
        start: start,
        end: end,
        communityPaths: [shortcut(status: PathService.statusPending)],
      ),
      () => fakeValhalla(requests),
    );

    expect(requests, hasLength(1));
    expect(pendingOnly.summary, isNot(contains('via community path')));
    expect(pendingOnly.directions, hasLength(2));
  });
}

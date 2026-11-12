import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:bike_nav/screens/mta_subway_service.dart';

void main() {
  final stationA = MtaStation(
    id: 'A',
    name: 'Alpha',
    point: const LatLng(40.0, -74.0),
    routes: const ['1'],
  );
  final stationB = MtaStation(
    id: 'B',
    name: 'Bravo',
    point: const LatLng(40.01, -74.0),
    routes: const ['1', '2'],
  );
  final stationC = MtaStation(
    id: 'C',
    name: 'Charlie',
    point: const LatLng(40.02, -74.0),
    routes: const ['2'],
  );
  final data = MtaSubwayData(
    stations: [stationA, stationB, stationC],
    scheduleDate: DateTime(2026, 11, 11),
    trips: [
      MtaScheduledTrip(
        route: '1',
        headsign: 'Bravo',
        calls: [
          MtaScheduledCall(
            stationId: 'A',
            arrival: DateTime(2026, 11, 11, 10, 4),
            departure: DateTime(2026, 11, 11, 10, 5),
          ),
          MtaScheduledCall(
            stationId: 'B',
            arrival: DateTime(2026, 11, 11, 10, 10),
            departure: DateTime(2026, 11, 11, 10, 11),
          ),
        ],
      ),
      MtaScheduledTrip(
        route: '2',
        headsign: 'Charlie',
        calls: [
          MtaScheduledCall(
            stationId: 'B',
            arrival: DateTime(2026, 11, 11, 10, 14),
            departure: DateTime(2026, 11, 11, 10, 15),
          ),
          MtaScheduledCall(
            stationId: 'C',
            arrival: DateTime(2026, 11, 11, 10, 20),
            departure: DateTime(2026, 11, 11, 10, 21),
          ),
        ],
      ),
    ],
  );

  test('selects distinct nearest MTA stations for both endpoints', () {
    final pair = data.nearestStationPair(
      start: const LatLng(40.001, -74.0),
      end: const LatLng(40.019, -74.0),
    );

    expect(pair.boarding.id, 'A');
    expect(pair.exit.id, 'C');
  });

  test('plans a scheduled subway journey with a transfer', () {
    final journey = data.findJourney(
      startStationId: 'A',
      endStationId: 'C',
      after: DateTime(2026, 11, 11, 10),
    )!;

    expect(journey, hasLength(2));
    expect(journey.map((leg) => leg.route), ['1', '2']);
    expect(journey.first.departure, DateTime(2026, 11, 11, 10, 5));
    expect(journey.last.arrival, DateTime(2026, 11, 11, 10, 20));
  });

  test('prefers an earlier transfer itinerary over a slower direct train', () {
    final dataWithDirectTrain = MtaSubwayData(
      stations: data.stations,
      scheduleDate: data.scheduleDate,
      trips: [
        ...data.trips,
        MtaScheduledTrip(
          route: '7',
          headsign: 'Charlie',
          calls: [
            MtaScheduledCall(
              stationId: 'A',
              arrival: DateTime(2026, 11, 11, 10, 4),
              departure: DateTime(2026, 11, 11, 10, 5),
            ),
            MtaScheduledCall(
              stationId: 'C',
              arrival: DateTime(2026, 11, 11, 10, 30),
              departure: DateTime(2026, 11, 11, 10, 31),
            ),
          ],
        ),
      ],
    );

    final journey = dataWithDirectTrain.findJourney(
      startStationId: 'A',
      endStationId: 'C',
      after: DateTime(2026, 11, 11, 10),
    )!;

    expect(journey.map((leg) => leg.route), ['1', '2']);
    expect(journey.last.arrival, DateTime(2026, 11, 11, 10, 20));
  });

  test(
    'returns future departures for only the selected route and direction',
    () {
      final dataWithReverseTrip = MtaSubwayData(
        stations: data.stations,
        scheduleDate: data.scheduleDate,
        trips: [
          ...data.trips,
          MtaScheduledTrip(
            route: '2',
            headsign: 'Bravo',
            calls: [
              MtaScheduledCall(
                stationId: 'C',
                arrival: DateTime(2026, 11, 11, 10, 14),
                departure: DateTime(2026, 11, 11, 10, 15),
              ),
              MtaScheduledCall(
                stationId: 'B',
                arrival: DateTime(2026, 11, 11, 10, 20),
                departure: DateTime(2026, 11, 11, 10, 21),
              ),
            ],
          ),
        ],
      );
      final departures = dataWithReverseTrip.nextDepartures(
        'B',
        after: DateTime(2026, 11, 11, 10, 0),
        route: '2',
        headsign: 'Charlie',
      );

      expect(departures, hasLength(1));
      expect(departures.single.route, '2');
      expect(departures.single.headsign, 'Charlie');
      expect(departures.single.departure, DateTime(2026, 11, 11, 10, 15));
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

class MtaStation {
  final String id;
  final String name;
  final LatLng point;
  final List<String> routes;

  const MtaStation({
    required this.id,
    required this.name,
    required this.point,
    required this.routes,
  });
}

class MtaScheduledCall {
  final String stationId;
  final DateTime arrival;
  final DateTime departure;

  const MtaScheduledCall({
    required this.stationId,
    required this.arrival,
    required this.departure,
  });
}

class MtaScheduledTrip {
  final String route;
  final String headsign;
  final String? shapeId;
  final List<MtaScheduledCall> calls;

  const MtaScheduledTrip({
    required this.route,
    required this.headsign,
    this.shapeId,
    required this.calls,
  });
}

class MtaDeparture {
  final String route;
  final String headsign;
  final DateTime departure;

  const MtaDeparture({
    required this.route,
    required this.headsign,
    required this.departure,
  });
}

class MtaTrainLeg {
  final String fromStationId;
  final String toStationId;
  final String route;
  final String headsign;
  final String fromStation;
  final String toStation;
  final DateTime departure;
  final DateTime arrival;
  final List<LatLng> pathPoints;

  const MtaTrainLeg({
    required this.fromStationId,
    required this.toStationId,
    required this.route,
    required this.headsign,
    required this.fromStation,
    required this.toStation,
    required this.departure,
    required this.arrival,
    required this.pathPoints,
  });
}

class MtaSubwayData {
  final List<MtaStation> stations;
  final List<MtaScheduledTrip> trips;
  final Map<String, List<LatLng>> shapes;
  final DateTime scheduleDate;

  const MtaSubwayData({
    required this.stations,
    required this.trips,
    this.shapes = const {},
    required this.scheduleDate,
  });

  List<MtaStation> nearestStations(LatLng point, {int limit = 6}) {
    final stationsWithDistance = [
      for (final station in stations)
        (
          station: station,
          distance: const Distance().as(LengthUnit.Meter, point, station.point),
        ),
    ]..sort((a, b) => a.distance.compareTo(b.distance));
    return stationsWithDistance
        .take(limit)
        .map((entry) => entry.station)
        .toList();
  }

  ({MtaStation boarding, MtaStation exit}) nearestStationPair({
    required LatLng start,
    required LatLng end,
  }) {
    final boardingCandidates = nearestStations(start, limit: 10);
    final exitCandidates = nearestStations(end, limit: 10);
    MtaStation? boarding;
    MtaStation? exit;
    var closestApproach = double.infinity;
    for (final boardingCandidate in boardingCandidates) {
      final startDistance = const Distance().as(
        LengthUnit.Meter,
        start,
        boardingCandidate.point,
      );
      for (final exitCandidate in exitCandidates) {
        if (boardingCandidate.id == exitCandidate.id) continue;
        final totalDistance =
            startDistance +
            const Distance().as(LengthUnit.Meter, end, exitCandidate.point);
        if (totalDistance < closestApproach) {
          closestApproach = totalDistance;
          boarding = boardingCandidate;
          exit = exitCandidate;
        }
      }
    }
    if (boarding == null || exit == null) {
      throw Exception('Could not find two distinct MTA subway stations.');
    }
    return (boarding: boarding, exit: exit);
  }

  List<MtaDeparture> nextDepartures(
    String stationId, {
    required DateTime after,
    required String route,
    required String headsign,
    int limit = 5,
  }) {
    final departures = <MtaDeparture>[];
    final before = after.add(const Duration(hours: 2));
    for (final trip in trips) {
      for (final call in trip.calls) {
        if (trip.route == route &&
            trip.headsign == headsign &&
            call.stationId == stationId &&
            !call.departure.isBefore(after) &&
            !call.departure.isAfter(before)) {
          departures.add(
            MtaDeparture(
              route: trip.route,
              headsign: trip.headsign,
              departure: call.departure,
            ),
          );
        }
      }
    }
    departures.sort((a, b) => a.departure.compareTo(b.departure));
    return departures.take(limit).toList();
  }

  List<MtaTrainLeg>? findJourney({
    required String startStationId,
    required String endStationId,
    required DateTime after,
    int maxTransfers = 2,
  }) {
    final stationsById = {for (final station in stations) station.id: station};
    var frontier = <String, (DateTime, List<MtaTrainLeg>)>{
      startStationId: (after, const []),
    };
    List<MtaTrainLeg>? bestJourney;
    DateTime? bestJourneyArrival;

    for (
      var transferCount = 0;
      transferCount <= maxTransfers && frontier.isNotEmpty;
      transferCount++
    ) {
      final nextFrontier = <String, (DateTime, List<MtaTrainLeg>)>{};
      for (final trip in trips) {
        for (
          var boardIndex = 0;
          boardIndex < trip.calls.length - 1;
          boardIndex++
        ) {
          final board = trip.calls[boardIndex];
          final state = frontier[board.stationId];
          if (state == null) continue;
          final reachableAt = state.$1.add(
            transferCount == 0 ? Duration.zero : const Duration(minutes: 3),
          );
          if (board.departure.isBefore(reachableAt)) continue;

          for (
            var exitIndex = boardIndex + 1;
            exitIndex < trip.calls.length;
            exitIndex++
          ) {
            final exit = trip.calls[exitIndex];
            final currentBest = nextFrontier[exit.stationId];
            if (currentBest != null && !exit.arrival.isBefore(currentBest.$1)) {
              continue;
            }
            final fromStation = stationsById[board.stationId];
            final toStation = stationsById[exit.stationId];
            if (fromStation == null || toStation == null) continue;

            final leg = MtaTrainLeg(
              fromStationId: board.stationId,
              toStationId: exit.stationId,
              route: trip.route,
              headsign: trip.headsign,
              fromStation: fromStation.name,
              toStation: toStation.name,
              departure: board.departure,
              arrival: exit.arrival,
              pathPoints: _trainPathPoints(
                trip,
                boardIndex,
                exitIndex,
                stationsById,
              ),
            );
            nextFrontier[exit.stationId] = (exit.arrival, [...state.$2, leg]);
          }
        }
      }
      final destination = nextFrontier[endStationId];
      if (destination != null &&
          (bestJourneyArrival == null ||
              destination.$1.isBefore(bestJourneyArrival))) {
        bestJourney = destination.$2;
        bestJourneyArrival = destination.$1;
      }
      frontier = nextFrontier;
    }
    return bestJourney;
  }

  List<LatLng> _trainPathPoints(
    MtaScheduledTrip trip,
    int boardIndex,
    int exitIndex,
    Map<String, MtaStation> stationsById,
  ) {
    final calls = trip.calls.sublist(boardIndex, exitIndex + 1);
    final stationPoints = [
      for (final call in calls)
        if (stationsById[call.stationId] case final station?)
          station.point,
    ];
    final shapePoints = shapes[trip.shapeId];
    if (shapePoints == null || shapePoints.length < 2) return stationPoints;

    final startPoint = stationsById[calls.first.stationId]?.point;
    final endPoint = stationsById[calls.last.stationId]?.point;
    if (startPoint == null || endPoint == null) return stationPoints;

    final distance = const Distance();
    int closestIndex(LatLng point, int firstIndex) {
      var closest = firstIndex;
      var closestDistance = double.infinity;
      for (var index = firstIndex; index < shapePoints.length; index++) {
        final currentDistance = distance.as(
          LengthUnit.Meter,
          point,
          shapePoints[index],
        );
        if (currentDistance < closestDistance) {
          closest = index;
          closestDistance = currentDistance;
        }
      }
      return closest;
    }

    final startIndex = closestIndex(startPoint, 0);
    final endIndex = closestIndex(endPoint, startIndex);
    if (endIndex <= startIndex) return stationPoints;
    return [
      startPoint,
      ...shapePoints.sublist(startIndex + 1, endIndex),
      endPoint,
    ];
  }
}

class MtaSubwayService {
  static const String feedUrl =
      'https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip';
  static const Duration refreshInterval = Duration(hours: 1);
  static Future<MtaSubwayData>? _inFlight;
  static MtaSubwayData? _cachedData;
  static DateTime? _cachedAt;

  static Future<MtaSubwayData> load() {
    final cached = _cachedData;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < refreshInterval) {
      return Future.value(cached);
    }
    return _inFlight ??= _load()
        .then((data) {
          _cachedData = data;
          _cachedAt = DateTime.now();
          return data;
        })
        .whenComplete(() => _inFlight = null);
  }

  static Future<MtaSubwayData> parseArchiveBytes(
    Uint8List bytes, {
    required DateTime now,
  }) async {
    final result = await compute(_parseGtfsArchive, <Object?>[
      bytes,
      now.toIso8601String(),
    ]);
    return _dataFromJson(result);
  }

  static Future<MtaSubwayData> _load() async {
    final directory = await getApplicationSupportDirectory();
    final feedFile = File(
      '${directory.path}${Platform.pathSeparator}mta-gtfs-supplemented.zip',
    );
    final hasCache = await feedFile.exists();
    final cacheAge = hasCache
        ? DateTime.now().difference(await feedFile.lastModified())
        : refreshInterval;

    if (!hasCache || cacheAge >= refreshInterval) {
      final response = await http
          .get(Uri.parse(feedUrl))
          .timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        throw Exception(
          'MTA schedule download failed (${response.statusCode}).',
        );
      }
      final tempFile = File('${feedFile.path}.download');
      await tempFile.writeAsBytes(response.bodyBytes, flush: true);
      if (hasCache) await feedFile.delete();
      await tempFile.rename(feedFile.path);
    }

    final bytes = await feedFile.readAsBytes();
    return parseArchiveBytes(bytes, now: DateTime.now());
  }

  static MtaSubwayData _dataFromJson(Map<String, dynamic> json) {
    final stations = (json['stations'] as List<dynamic>).map((value) {
      final station = value as Map<String, dynamic>;
      return MtaStation(
        id: station['id'] as String,
        name: station['name'] as String,
        point: LatLng(
          (station['lat'] as num).toDouble(),
          (station['lon'] as num).toDouble(),
        ),
        routes: (station['routes'] as List<dynamic>).cast<String>(),
      );
    }).toList();
    final shapesJson =
        json['shapes'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final shapes = shapesJson.map(
      (shapeId, values) => MapEntry(
        shapeId,
        (values as List<dynamic>).map((value) {
          final point = value as Map<String, dynamic>;
          return LatLng(
            (point['lat'] as num).toDouble(),
            (point['lon'] as num).toDouble(),
          );
        }).toList(),
      ),
    );
    final trips = (json['trips'] as List<dynamic>).map((value) {
      final trip = value as Map<String, dynamic>;
      return MtaScheduledTrip(
        route: trip['route'] as String,
        headsign: trip['headsign'] as String,
        shapeId: trip['shapeId'] as String?,
        calls: (trip['calls'] as List<dynamic>).map((callValue) {
          final call = callValue as Map<String, dynamic>;
          return MtaScheduledCall(
            stationId: call['stationId'] as String,
            arrival: DateTime.fromMillisecondsSinceEpoch(
              call['arrival'] as int,
            ),
            departure: DateTime.fromMillisecondsSinceEpoch(
              call['departure'] as int,
            ),
          );
        }).toList(),
      );
    }).toList();
    return MtaSubwayData(
      stations: stations,
      trips: trips,
      shapes: shapes,
      scheduleDate: DateTime.parse(json['scheduleDate'] as String),
    );
  }
}

Map<String, dynamic> _parseGtfsArchive(List<Object?> args) {
  final bytes = args[0] as Uint8List;
  final now = DateTime.parse(args[1] as String);
  final archive = ZipDecoder().decodeBytes(bytes);
  final stopsFile = archive.find('stops.txt');
  final routesFile = archive.find('routes.txt');
  final tripsFile = archive.find('trips.txt');
  final calendarFile = archive.find('calendar.txt');
  final exceptionsFile = archive.find('calendar_dates.txt');
  final stopTimesFile = archive.find('stop_times.txt');
  final shapesFile = archive.find('shapes.txt');
  if ([
    stopsFile,
    routesFile,
    tripsFile,
    calendarFile,
    stopTimesFile,
  ].contains(null)) {
    throw const FormatException('MTA GTFS feed is missing required tables.');
  }

  final stationRows = _rows(stopsFile!);
  final stationById = <String, Map<String, dynamic>>{};
  final stopToStationId = <String, String>{};
  for (final row in stationRows) {
    final id = row['stop_id'] ?? '';
    final parent = row['parent_station'] ?? '';
    final locationType = row['location_type'] ?? '';
    if (locationType == '1' || (parent.isEmpty && id.isNotEmpty)) {
      final latitude = double.tryParse(row['stop_lat'] ?? '');
      final longitude = double.tryParse(row['stop_lon'] ?? '');
      if (latitude == null || longitude == null) continue;
      stationById[id] = {
        'id': id,
        'name': row['stop_name'] ?? 'Subway station',
        'lat': latitude,
        'lon': longitude,
        'routes': <String>{},
      };
    }
    if (id.isNotEmpty) stopToStationId[id] = parent.isEmpty ? id : parent;
  }

  final routeNames = <String, String>{};
  for (final row in _rows(routesFile!)) {
    final id = row['route_id'] ?? '';
    final name = row['route_short_name'] ?? '';
    if (id.isNotEmpty && name.isNotEmpty) routeNames[id] = name;
  }

  final calendarRows = _rows(calendarFile!).toList();
  final exceptionRows = exceptionsFile == null
      ? const <Map<String, String>>[]
      : _rows(exceptionsFile).toList();
  Set<String> activeServicesOn(DateTime date) {
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    final weekday = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ][date.weekday - 1];
    final active = <String>{};
    for (final row in calendarRows) {
      if (row[weekday] == '1' &&
          dateKey.compareTo(row['start_date'] ?? '') >= 0 &&
          dateKey.compareTo(row['end_date'] ?? '') <= 0) {
        active.add(row['service_id'] ?? '');
      }
    }
    for (final row in exceptionRows) {
      if (row['date'] != dateKey) continue;
      final serviceId = row['service_id'] ?? '';
      if (row['exception_type'] == '1') {
        active.add(serviceId);
      } else if (row['exception_type'] == '2') {
        active.remove(serviceId);
      }
    }
    return active;
  }

  final activeServicesByOffset = {
    for (final offset in [-1, 0])
      offset: activeServicesOn(now.add(Duration(days: offset))),
  };
  final tripMetadata = <String, List<Map<String, String>>>{};
  for (final row in _rows(tripsFile!)) {
    final serviceId = row['service_id'] ?? '';
    for (final entry in activeServicesByOffset.entries) {
      if (!entry.value.contains(serviceId)) continue;
      tripMetadata.putIfAbsent(row['trip_id'] ?? '', () => []).add({
        'offset': entry.key.toString(),
        'route': routeNames[row['route_id']] ?? row['route_id'] ?? '',
        'headsign': row['trip_headsign'] ?? '',
        'shapeId': row['shape_id'] ?? '',
      });
    }
  }

  final relevantShapeIds = <String>{};
  for (final metadataList in tripMetadata.values) {
    for (final metadata in metadataList) {
      final shapeId = metadata['shapeId'];
      if (shapeId != null && shapeId.isNotEmpty) relevantShapeIds.add(shapeId);
    }
  }
  final shapeRows = <String, List<(int, LatLng)>>{};
  if (shapesFile != null && relevantShapeIds.isNotEmpty) {
    for (final row in _rows(shapesFile)) {
      final shapeId = row['shape_id'] ?? '';
      if (!relevantShapeIds.contains(shapeId)) continue;
      final latitude = double.tryParse(row['shape_pt_lat'] ?? '');
      final longitude = double.tryParse(row['shape_pt_lon'] ?? '');
      final sequence = int.tryParse(row['shape_pt_sequence'] ?? '');
      if (latitude == null || longitude == null || sequence == null) continue;
      shapeRows
          .putIfAbsent(shapeId, () => [])
          .add((sequence, LatLng(latitude, longitude)));
    }
  }
  final shapes = <String, List<LatLng>>{
    for (final entry in shapeRows.entries)
      entry.key: (entry.value..sort((a, b) => a.$1.compareTo(b.$1)))
          .map((point) => point.$2)
          .toList(),
  };

  final firstWindow = now.subtract(const Duration(hours: 2));
  final lastWindow = now.add(const Duration(hours: 8));
  final trips = <Map<String, dynamic>>[];
  String? currentTripId;
  List<Map<String, String>>? currentMetadata;
  final currentCalls = <Map<String, dynamic>>[];

  void flushTrip() {
    if (currentTripId == null ||
        currentMetadata == null ||
        currentCalls.length < 2) {
      return;
    }
    final midnight = DateTime(now.year, now.month, now.day);
    for (final metadata in currentMetadata) {
      final serviceMidnight = midnight.add(
        Duration(days: int.parse(metadata['offset']!)),
      );
      final calls = <Map<String, dynamic>>[];
      var tripInWindow = false;
      for (final rawCall in currentCalls) {
        final arrival = _scheduledTime(
          serviceMidnight,
          rawCall['arrivalTime'] as String,
        );
        final departure = _scheduledTime(
          serviceMidnight,
          rawCall['departureTime'] as String,
        );
        if (arrival == null || departure == null) continue;
        if (!departure.isBefore(firstWindow) &&
            !departure.isAfter(lastWindow)) {
          tripInWindow = true;
        }
        calls.add({
          'stationId': rawCall['stationId'],
          'arrival': arrival.millisecondsSinceEpoch,
          'departure': departure.millisecondsSinceEpoch,
        });
      }
      if (tripInWindow && calls.length > 1) {
        trips.add({
          'route': metadata['route'] ?? '',
          'headsign': metadata['headsign'] ?? '',
          'shapeId': metadata['shapeId'],
          'calls': calls,
        });
        for (final call in calls) {
          final station = stationById[call['stationId']];
          if (station != null) {
            (station['routes'] as Set<String>).add(metadata['route'] ?? '');
          }
        }
      }
    }
  }

  for (final row in _rows(stopTimesFile!)) {
    final tripId = row['trip_id'] ?? '';
    if (tripId != currentTripId) {
      flushTrip();
      currentTripId = tripId;
      currentMetadata = tripMetadata[tripId];
      currentCalls.clear();
    }
    if (currentMetadata == null) continue;
    final stationId = stopToStationId[row['stop_id'] ?? ''];
    if (stationId == null || !stationById.containsKey(stationId)) continue;
    final arrivalTime = row['arrival_time'] ?? '';
    final departureTime = row['departure_time'] ?? '';
    if (arrivalTime.isEmpty && departureTime.isEmpty) continue;
    currentCalls.add({
      'stationId': stationId,
      'arrivalTime': arrivalTime.isEmpty ? departureTime : arrivalTime,
      'departureTime': departureTime.isEmpty ? arrivalTime : departureTime,
    });
  }
  flushTrip();

  return {
    'scheduleDate': DateTime(now.year, now.month, now.day).toIso8601String(),
    'stations': stationById.values
        .map(
          (station) => {
            ...station,
            'routes': (station['routes'] as Set<String>).toList()..sort(),
          },
        )
        .toList(),
    'trips': trips,
    'shapes': {
      for (final entry in shapes.entries)
        entry.key: [
          for (final point in entry.value)
            {'lat': point.latitude, 'lon': point.longitude},
        ],
    },
  };
}

Iterable<Map<String, String>> _rows(ArchiveFile file) sync* {
  final stream = file.getContent();
  if (stream == null) return;
  final lines = _lines(stream).iterator;
  if (!lines.moveNext()) return;
  final headers = _parseCsvLine(lines.current);
  while (lines.moveNext()) {
    final values = _parseCsvLine(lines.current);
    if (values.length != headers.length) continue;
    yield {
      for (var index = 0; index < headers.length; index++)
        headers[index]: values[index],
    };
  }
}

Iterable<String> _lines(InputStream stream) sync* {
  final pending = BytesBuilder(copy: false);
  final buffer = Uint8List(64 * 1024);
  while (!stream.isEOS) {
    final count = math.min(buffer.length, stream.length);
    if (count == 0) break;
    final read = stream.readInto(buffer, 0, count);
    var lineStart = 0;
    for (var index = 0; index < read; index++) {
      if (buffer[index] != 10) continue;
      pending.add(buffer.sublist(lineStart, index));
      var line = pending.takeBytes();
      if (line.isNotEmpty && line.last == 13) {
        line = line.sublist(0, line.length - 1);
      }
      yield utf8.decode(line);
      lineStart = index + 1;
    }
    pending.add(buffer.sublist(lineStart, read));
  }
  final lastLine = pending.takeBytes();
  if (lastLine.isNotEmpty) yield utf8.decode(lastLine);
}

List<String> _parseCsvLine(String line) {
  final values = <String>[];
  final value = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        value.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      values.add(value.toString());
      value.clear();
    } else {
      value.write(character);
    }
  }
  values.add(value.toString());
  return values;
}

DateTime? _scheduledTime(DateTime midnight, String value) {
  final parts = value.split(':');
  if (parts.length != 3) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  final second = int.tryParse(parts[2]);
  if (hour == null || minute == null || second == null) return null;
  return midnight.add(Duration(hours: hour, minutes: minute, seconds: second));
}

MtaSubwayData parseMtaScheduleJson(Map<String, dynamic> json) =>
    MtaSubwayService._dataFromJson(json);

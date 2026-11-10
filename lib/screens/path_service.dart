import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// One recorded GPS fix. Time and accuracy are optional so paths saved before
// they were recorded still load.
class TrackPoint {
  final LatLng point;
  final DateTime? time;
  final double? accuracy;

  const TrackPoint({required this.point, this.time, this.accuracy});

  Map<String, dynamic> toMap() => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    if (time != null) 'time': time!.toIso8601String(),
    if (accuracy != null) 'accuracy': accuracy,
  };

  static TrackPoint? tryParse(Object? value) {
    if (value is! Map) return null;
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if (latitude is! num || longitude is! num) return null;
    final time = value['time'];
    final accuracy = value['accuracy'];
    return TrackPoint(
      point: LatLng(latitude.toDouble(), longitude.toDouble()),
      time: time is String ? DateTime.tryParse(time) : null,
      accuracy: accuracy is num ? accuracy.toDouble() : null,
    );
  }
}

// A community-submitted bike path.
class CommunityPath {
  final String id;
  final String submitter;
  final String startName;
  final String endName;
  final String description;
  final String status;
  final String date;
  final List<TrackPoint> points;
  final double lengthMeters;
  final double durationSeconds;
  final String bikeType;
  final bool oneWay;
  final List<String> confirmations;

  // Any other saved fields (for example startLatitude) are kept as they are.
  final Map<String, dynamic> extra;

  const CommunityPath({
    required this.id,
    required this.submitter,
    required this.startName,
    required this.endName,
    required this.points,
    required this.lengthMeters,
    required this.date,
    this.description = '',
    this.status = PathService.statusPending,
    this.durationSeconds = 0,
    this.bikeType = '',
    this.oneWay = false,
    this.confirmations = const [],
    this.extra = const {},
  });

  bool get isVerified =>
      status.toLowerCase() == PathService.statusVerified.toLowerCase();

  bool get isPending =>
      status.toLowerCase() == PathService.statusPending.toLowerCase();

  String get label => '$startName to $endName';

  List<LatLng> get polyline => points.map((p) => p.point).toList();

  bool isSubmittedBy(String email) =>
      submitter.isNotEmpty && submitter.toLowerCase() == email.toLowerCase();

  bool isConfirmedBy(String email) =>
      confirmations.any((user) => user.toLowerCase() == email.toLowerCase());

  CommunityPath copyWith({String? status, List<String>? confirmations}) {
    return CommunityPath(
      id: id,
      submitter: submitter,
      startName: startName,
      endName: endName,
      points: points,
      lengthMeters: lengthMeters,
      date: date,
      description: description,
      status: status ?? this.status,
      durationSeconds: durationSeconds,
      bikeType: bikeType,
      oneWay: oneWay,
      confirmations: confirmations ?? this.confirmations,
      extra: extra,
    );
  }

  Map<String, dynamic> toMap() => {
    ...extra,
    'id': id,
    'submitter': submitter,
    'start': startName,
    'end': endName,
    'description': description,
    'status': status,
    'date': date,
    'lengthMeters': lengthMeters,
    'durationSeconds': durationSeconds,
    'bikeType': bikeType,
    'oneWay': oneWay,
    'confirmations': confirmations,
    'points': points.map((p) => p.toMap()).toList(),
  };

  // Reads a saved path. Fields added after the first Add Path version get
  // defaults, so paths already saved on a device still load.
  static CommunityPath? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);

    final savedPoints = map['points'];
    final points = <TrackPoint>[];
    if (savedPoints is List) {
      for (final item in savedPoints) {
        final point = TrackPoint.tryParse(item);
        if (point != null) points.add(point);
      }
    }

    final date = map['date']?.toString() ?? '';
    final savedId = map['id'];
    final savedLength = map['lengthMeters'];
    final savedDuration = map['durationSeconds'];
    final savedConfirmations = map['confirmations'];

    var durationSeconds = 0.0;
    if (savedDuration is num) {
      durationSeconds = savedDuration.toDouble();
    } else if (points.length > 1 &&
        points.first.time != null &&
        points.last.time != null) {
      durationSeconds =
          points.last.time!.difference(points.first.time!).inMilliseconds /
          1000;
    }

    return CommunityPath(
      id: savedId is String && savedId.isNotEmpty ? savedId : 'legacy-$date',
      submitter: map['submitter']?.toString() ?? '',
      startName: map['start']?.toString() ?? 'Start',
      endName: map['end']?.toString() ?? 'End',
      description: map['description']?.toString() ?? '',
      status: map['status']?.toString() ?? PathService.statusPending,
      date: date,
      points: points,
      lengthMeters: savedLength is num
          ? savedLength.toDouble()
          : PathService.trackLength(points.map((p) => p.point).toList()),
      durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
      bikeType: map['bikeType']?.toString() ?? '',
      oneWay: map['oneWay'] == true,
      confirmations: savedConfirmations is List
          ? savedConfirmations.map((user) => user.toString()).toList()
          : const [],
      extra: map,
    );
  }
}

// A verified path lined up for one trip, in the direction it would be ridden.
class PathCandidate {
  final CommunityPath path;
  final bool reversed;
  final List<LatLng> points;
  final double estimateMeters;

  const PathCandidate({
    required this.path,
    required this.reversed,
    required this.points,
    required this.estimateMeters,
  });

  LatLng get entry => points.first;
  LatLng get exit => points.last;

  String get label => reversed
      ? '${path.endName} to ${path.startName}'
      : '${path.startName} to ${path.endName}';
}

// Reads and writes community paths. Screens only call these methods, so the
// storage behind them can move to a shared backend later.
class PathService {
  static const String _pathsKey = 'bike_nav_paths';

  static const String statusPending = 'Pending';
  static const String statusVerified = 'Verified';

  // Confirmations from other riders needed before a path is used in routing.
  static const int confirmationsToVerify = 3;

  // Recording quality bar.
  static const int minTrackPoints = 10;
  static const double minTrackMeters = 100;
  static const double maxFixAccuracyMeters = 30;
  static const double maxSpeedMetersPerSecond = 20;

  // About 18 km/h, used when a path has no recorded ride duration.
  static const double fallbackMetersPerSecond = 5;

  // Skip a path if going via it is this much longer than the normal route.
  static const double maxDetourFactor = 1.3;

  static Future<List<dynamic>> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_pathsKey);
    if (data == null) return [];
    final saved = jsonDecode(data);
    return saved is List ? List<dynamic>.from(saved) : [];
  }

  static Future<void> _save(List<dynamic> paths) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_pathsKey, jsonEncode(paths));
    if (!saved) throw StateError('Could not save path data.');
  }

  static Future<List<CommunityPath>> loadPaths() async {
    final saved = await _loadSaved();
    final paths = <CommunityPath>[];
    for (final item in saved) {
      final path = CommunityPath.tryParse(item);
      if (path != null) paths.add(path);
    }
    return paths;
  }

  static Future<List<CommunityPath>> loadVerifiedPaths() async {
    final paths = await loadPaths();
    return paths.where((path) => path.isVerified).toList();
  }

  static Future<void> savePath(CommunityPath path) async {
    final saved = await _loadSaved();
    saved.add(path.toMap());
    await _save(saved);
  }

  // Records that a rider rode this path. Each rider counts once and the
  // submitter cannot confirm their own path. The path becomes verified once
  // it has enough confirmations. Returns the path as it is after the call.
  static Future<CommunityPath?> confirmPath(String id, String userEmail) async {
    final saved = await _loadSaved();
    for (var index = 0; index < saved.length; index++) {
      final path = CommunityPath.tryParse(saved[index]);
      if (path == null || path.id != id) continue;

      if (userEmail.trim().isEmpty ||
          path.isSubmittedBy(userEmail) ||
          path.isConfirmedBy(userEmail)) {
        return path;
      }

      final confirmations = [...path.confirmations, userEmail];
      final updated = path.copyWith(
        confirmations: confirmations,
        status: path.isPending && confirmations.length >= confirmationsToVerify
            ? statusVerified
            : path.status,
      );
      saved[index] = updated.toMap();
      await _save(saved);
      return updated;
    }
    return null;
  }

  static String newId() {
    final random = math.Random().nextInt(0x7fffffff);
    return '${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  // Straight-line distance in meters.
  static double metersBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    const toRadians = math.pi / 180;
    final lat1 = a.latitude * toRadians;
    final lat2 = b.latitude * toRadians;
    final dLat = lat2 - lat1;
    final dLon = (b.longitude - a.longitude) * toRadians;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  static double trackLength(List<LatLng> points) {
    var meters = 0.0;
    for (var index = 1; index < points.length; index++) {
      meters += metersBetween(points[index - 1], points[index]);
    }
    return meters;
  }

  // Whether a new GPS fix is good enough to add to a recording. Drops
  // low-accuracy fixes and jumps no bike could make.
  static bool shouldKeepFix(TrackPoint? previous, TrackPoint next) {
    final accuracy = next.accuracy;
    if (accuracy != null && accuracy > maxFixAccuracyMeters) return false;
    if (previous == null) return true;

    final previousTime = previous.time;
    final nextTime = next.time;
    if (previousTime != null && nextTime != null) {
      final seconds = nextTime.difference(previousTime).inMilliseconds / 1000;
      if (seconds <= 0) return false;
      final meters = metersBetween(previous.point, next.point);
      if (meters / seconds > maxSpeedMetersPerSecond) return false;
    }
    return true;
  }

  // Returns why a recording cannot be submitted, or null if it is fine.
  static String? validateTrack(List<TrackPoint> points) {
    if (points.isEmpty) return 'Please record a bike route first';
    if (points.length < minTrackPoints) {
      return 'Recording is too short. Keep riding to record more GPS points.';
    }
    final meters = trackLength(points.map((p) => p.point).toList());
    if (meters < minTrackMeters) {
      return 'Recording is too short. Ride at least '
          '${minTrackMeters.round()} m before submitting.';
    }
    return null;
  }

  // Verified paths worth trying for a trip, closest fit first. A path is
  // skipped when going via it is much longer than the normal route.
  static List<PathCandidate> candidatesFor({
    required LatLng start,
    required LatLng end,
    required double baselineMeters,
    required List<CommunityPath> paths,
  }) {
    final candidates = <PathCandidate>[];
    for (final path in paths) {
      if (!path.isVerified || path.points.length < 2) continue;
      final forward = path.polyline;
      for (final reversed in [false, if (!path.oneWay) true]) {
        final points = reversed ? forward.reversed.toList() : forward;
        final estimate =
            metersBetween(start, points.first) +
            path.lengthMeters +
            metersBetween(points.last, end);
        if (estimate > baselineMeters * maxDetourFactor) continue;
        candidates.add(
          PathCandidate(
            path: path,
            reversed: reversed,
            points: points,
            estimateMeters: estimate,
          ),
        );
      }
    }
    candidates.sort((a, b) => a.estimateMeters.compareTo(b.estimateMeters));
    return candidates;
  }

  static String formatLength(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

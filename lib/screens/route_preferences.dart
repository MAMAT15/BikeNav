/// How a trip should be ridden: the rider's bike and their route choices,
/// turned into Valhalla bicycle costing options.
///
/// This file has no Flutter imports and takes the bike profile fields as
/// plain values, so the mapping can be tuned here without touching routing
/// code.
class RoutePreferences {
  /// Valhalla bike type: Road, Hybrid, Cross or Mountain.
  final String bicycleType;

  /// Average cruising speed on flat, smooth roads. Null keeps Valhalla's
  /// default for [bicycleType].
  final double? cyclingSpeedKph;

  final bool isElectric;

  /// Stay off roads shared with traffic where possible.
  final bool avoidBusyRoads;

  /// Avoid climbs. Overrides the e-bike hill setting.
  final bool avoidHills;

  /// Rank routes by distance instead of time.
  final bool shortest;

  const RoutePreferences({
    this.bicycleType = 'Hybrid',
    this.cyclingSpeedKph,
    this.isElectric = false,
    this.avoidBusyRoads = false,
    this.avoidHills = false,
    this.shortest = false,
  });

  // Valhalla rejects cycling speeds outside 5–60 km/h.
  static const double minSpeedKph = 5;
  static const double maxSpeedKph = 60;

  /// Bike profile type → Valhalla `bicycle_type`. Anything missing
  /// (including "Other" and no profile) routes as Hybrid, Valhalla's default.
  static const Map<String, String> valhallaTypes = {
    'City / commuter': 'Hybrid',
    'Folding': 'Hybrid',
    'Cargo / utility': 'Hybrid',
    'Hybrid': 'Hybrid',
    'Road': 'Road',
  };

  // Starting estimates, to tune after test rides. Pedal bikes not listed
  // here use Valhalla's default speed for their type.
  static const Map<String, double> pedalSpeedsKph = {
    'Folding': 16,
    'Cargo / utility': 15,
  };

  // E-bike cruising speeds by class (below the motor-assist limits, since
  // this is an average, not a top speed).
  static const Map<int, double> electricSpeedsKph = {1: 24, 2: 24, 3: 28};
  static const double defaultElectricSpeedKph = 24;

  // Valhalla's default use_hills is 0.25; e-bike riders mind climbs less.
  static const double electricUseHills = 0.5;

  factory RoutePreferences.forBike({
    String? bikeType,
    bool isElectric = false,
    int? electricClass,
    bool avoidBusyRoads = false,
    bool avoidHills = false,
    bool shortest = false,
  }) {
    return RoutePreferences(
      bicycleType: valhallaTypes[bikeType] ?? 'Hybrid',
      cyclingSpeedKph: speedFor(
        bikeType,
        isElectric: isElectric,
        electricClass: electricClass,
      ),
      isElectric: isElectric,
      avoidBusyRoads: avoidBusyRoads,
      avoidHills: avoidHills,
      shortest: shortest,
    );
  }

  /// The cruising speed to send, or null for Valhalla's default.
  static double? speedFor(
    String? bikeType, {
    required bool isElectric,
    int? electricClass,
  }) {
    final speed = isElectric
        ? (electricSpeedsKph[electricClass] ?? defaultElectricSpeedKph)
        : pedalSpeedsKph[bikeType];
    return speed?.clamp(minSpeedKph, maxSpeedKph).toDouble();
  }

  /// The "bicycle" entry of Valhalla's `costing_options`.
  Map<String, dynamic> toCostingOptions({required bool avoidFerries}) => {
    'bicycle_type': bicycleType,
    if (cyclingSpeedKph != null) 'cycling_speed': cyclingSpeedKph,
    if (avoidBusyRoads) 'use_roads': 0.0,
    if (avoidHills)
      'use_hills': 0.0
    else if (isElectric)
      'use_hills': electricUseHills,
    if (shortest) 'shortest': true,
    if (avoidFerries) 'use_ferry': 0,
  };
}

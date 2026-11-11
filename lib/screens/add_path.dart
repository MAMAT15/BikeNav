import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart' show AuthService;
import 'path_service.dart';

class AddPathScreen extends StatefulWidget {
  final String userEmail;

  const AddPathScreen({super.key, this.userEmail = ''});

  @override
  State<AddPathScreen> createState() => _AddPathScreenState();
}

class _AddPathScreenState extends State<AddPathScreen> {
  final start = TextEditingController();
  final end = TextEditingController();
  final description = TextEditingController();

  List<Position> positions = [];

  StreamSubscription<Position>? positionStream;

  bool isRecording = false;
  bool searchingStart = false;
  bool searchingEnd = false;

  Timer? startTimer;
  Timer? endTimer;

  int startVersion = 0;
  int endVersion = 0;

  List<_PlaceSuggestion> startSuggestions = [];
  List<_PlaceSuggestion> endSuggestions = [];

  _PlaceSuggestion? selectedStart;
  _PlaceSuggestion? selectedEnd;

  // Search places with Photon
  void searchPlaces(String query, bool isStart) {
    final text = query.trim();

    if (isStart) {
      startTimer?.cancel();
      startVersion++;
      selectedStart = null;
      startSuggestions = [];
      searchingStart = false;
    } else {
      endTimer?.cancel();
      endVersion++;
      selectedEnd = null;
      endSuggestions = [];
      searchingEnd = false;
    }

    setState(() {});

    if (text.length < 3) return;

    final version = isStart ? startVersion : endVersion;

    final timer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final uri = Uri.https('photon.komoot.io', '/api/', {
          'q': text,
          'limit': '8',
        });

        if (isStart) {
          setState(() => searchingStart = true);
        } else {
          setState(() => searchingEnd = true);
        }

        final response = await http.get(
          uri,
          headers: const {'User-Agent': 'BikeNav/1.0'},
        );

        if (response.statusCode != 200) {
          throw Exception('Search failed');
        }

        final data = jsonDecode(response.body);
        final features = data['features'] as List;

        List<_PlaceSuggestion> results = [];

        for (var item in features) {
          final properties = item['properties'];
          final coordinates = item['geometry']['coordinates'];

          final name =
              properties['name'] ??
              properties['street'] ??
              properties['city'] ??
              'Place';

          final details =
              [properties['street'], properties['city'], properties['state']]
                  .where((value) => value != null && value.toString() != name)
                  .join(', ');

          results.add(
            _PlaceSuggestion(
              name: name.toString(),
              detail: details,
              point: LatLng(
                (coordinates[1] as num).toDouble(),
                (coordinates[0] as num).toDouble(),
              ),
            ),
          );
        }

        if (!mounted) return;

        if (isStart && version == startVersion && start.text.trim() == text) {
          setState(() {
            startSuggestions = results;
            searchingStart = false;
          });
        } else if (!isStart &&
            version == endVersion &&
            end.text.trim() == text) {
          setState(() {
            endSuggestions = results;
            searchingEnd = false;
          });
        }
      } catch (_) {
        if (!mounted) return;

        if (isStart && version == startVersion) {
          setState(() {
            startSuggestions = [];
            searchingStart = false;
          });
        } else if (!isStart && version == endVersion) {
          setState(() {
            endSuggestions = [];
            searchingEnd = false;
          });
        }
      }
    });

    if (isStart) {
      startTimer = timer;
    } else {
      endTimer = timer;
    }
  }

  // Select a place from suggestions
  void selectPlace(_PlaceSuggestion place, bool isStart) {
    setState(() {
      if (isStart) {
        start.text = place.name;
        selectedStart = place;
        startSuggestions = [];
      } else {
        end.text = place.name;
        selectedEnd = place;
        endSuggestions = [];
      }
    });

    FocusScope.of(context).unfocus();
  }

  TrackPoint toTrackPoint(Position position) {
    return TrackPoint(
      point: LatLng(position.latitude, position.longitude),
      time: position.timestamp,
      accuracy: position.accuracy,
    );
  }

  // On Android a foreground notification keeps GPS running while the
  // phone is locked.
  LocationSettings recordingSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'BikeNav is recording your ride',
          notificationText: 'Open BikeNav to stop recording.',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  // Start GPS recording
  Future<void> startRecording() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!mounted) return;

    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required')),
      );
      return;
    }

    positions.clear();

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: recordingSettings(),
        ).listen(
          (Position position) {
            if (!mounted) return;

            // Skip low-accuracy fixes and GPS jumps
            final previous = positions.isEmpty
                ? null
                : toTrackPoint(positions.last);
            final next = toTrackPoint(position);
            if (!PathService.shouldKeepFix(previous, next)) {
              // A lone first point is often an old cached location. Start
              // again from the new fix so it cannot block the recording.
              if (positions.length == 1 &&
                  PathService.shouldKeepFix(null, next)) {
                setState(() {
                  positions = [position];
                });
              }
              return;
            }

            setState(() {
              positions.add(position);
            });
          },
          onError: (Object error) {
            if (!mounted) return;

            stopRecording();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location updates stopped. Recording paused.'),
              ),
            );
          },
        );

    setState(() {
      isRecording = true;
    });
  }

  // Stop GPS recording
  Future<void> stopRecording() async {
    await positionStream?.cancel();
    positionStream = null;

    if (!mounted) return;

    setState(() {
      isRecording = false;
    });
  }

  // Submit path
  Future<void> submitPath() async {
    if (selectedStart == null || selectedEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both locations from the suggestions'),
        ),
      );
      return;
    }

    // A route can only be submitted once it is recorded and stopped.
    if (isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop recording before submitting')),
      );
      return;
    }

    final track = positions.map(toTrackPoint).toList();
    final problem =
        PathService.validateTrack(track) ??
        PathService.validateReachesEnd(track, selectedEnd!.point);

    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem)),
      );
      return;
    }

    String bikeType = '';

    try {
      final account = await AuthService.findAccount(widget.userEmail);
      bikeType = account?.bikeProfile?.type ?? '';
    } catch (_) {
      bikeType = '';
    }

    final firstTime = track.first.time;
    final lastTime = track.last.time;
    double durationSeconds = 0;

    if (firstTime != null && lastTime != null) {
      durationSeconds = lastTime.difference(firstTime).inMilliseconds / 1000;
    }

    // Routing uses the recorded track's first and last points.
    // The selected places are kept as labels.
    final newPath = CommunityPath(
      id: PathService.newId(),
      submitter: widget.userEmail,
      startName: selectedStart!.name,
      endName: selectedEnd!.name,
      description: description.text,
      status: PathService.statusPending,
      date: DateTime.now().toString(),
      points: track,
      lengthMeters: PathService.trackLength(
        track.map((p) => p.point).toList(),
      ),
      durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
      bikeType: bikeType,
      extra: {
        'startLatitude': selectedStart!.point.latitude,
        'startLongitude': selectedStart!.point.longitude,
        'endLatitude': selectedEnd!.point.latitude,
        'endLongitude': selectedEnd!.point.longitude,
      },
    );

    try {
      await PathService.savePath(newPath);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the path. Try again.')),
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Path submitted successfully!')),
    );

    Navigator.pop(context);
  }

  // Section title
  Widget sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Location input
  Widget locationInput(
    TextEditingController controller,
    String hint,
    Color iconColor,
    bool isStart,
  ) {
    return TextField(
      controller: controller,
      onChanged: (value) => searchPlaces(value, isStart),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.location_on_outlined, color: iconColor),
        suffixIcon: (isStart ? searchingStart : searchingEnd)
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  // Place suggestion list
  Widget suggestionList(List<_PlaceSuggestion> suggestions, bool isStart) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: suggestions.map((place) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined, color: Colors.grey),
            title: Text(place.name),
            subtitle: place.detail.isEmpty ? null : Text(place.detail),
            onTap: () => selectPlace(place, isStart),
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    startTimer?.cancel();
    endTimer?.cancel();
    positionStream?.cancel();

    start.dispose();
    end.dispose();
    description.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Submit is only available once a route is recorded and stopped.
    final canSubmit = !isRecording && positions.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a Bike Path'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add a Bike Path',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 24),

              // 1. Starting Point
              sectionTitle('1. Choose Starting Point'),

              const SizedBox(height: 10),

              locationInput(
                start,
                'Select starting location',
                Colors.green,
                true,
              ),

              suggestionList(startSuggestions, true),

              const SizedBox(height: 18),

              // 2. Destination
              sectionTitle('2. Choose Destination'),

              const SizedBox(height: 10),

              locationInput(end, 'Select destination', Colors.red, false),

              suggestionList(endSuggestions, false),

              const SizedBox(height: 18),

              // 3. Record Ride
              sectionTitle('3. Record Your Ride'),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 110,
                child: ElevatedButton(
                  onPressed: isRecording ? stopRecording : startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF3EE),
                    foregroundColor: const Color(0xFF087B43),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRecording
                            ? Icons.stop_circle_outlined
                            : Icons.directions_bike,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRecording ? 'Stop Recording' : 'Start Recording',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isRecording
                            ? 'Recording GPS...'
                            : 'Record GPS location while riding',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Recorded GPS points: ${positions.length} · '
                '${PathService.formatLength(PathService.trackLength(positions.map((p) => LatLng(p.latitude, p.longitude)).toList()))}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),

              if (isRecording && positions.isEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'Waiting for a GPS signal. Recording works best outdoors.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB05A00)),
                ),
              ],

              const SizedBox(height: 22),

              // 4. Submit for Review
              sectionTitle('4. Submit for Review'),

              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  canSubmit
                      ? 'Upload recorded GPS route and optional description.'
                      : isRecording
                      ? 'Stop recording to submit your route.'
                      : 'Record a route and stop recording to submit it.',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: description,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Description (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: canSubmit ? submitPath : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2878F0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Submit Path',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Place search result
class _PlaceSuggestion {
  final String name;
  final String detail;
  final LatLng point;

  _PlaceSuggestion({
    required this.name,
    required this.detail,
    required this.point,
  });
}

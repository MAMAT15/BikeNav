import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'path_service.dart';

// Lists the rider's own submissions and pending paths they can confirm.
class CommunityPathsScreen extends StatefulWidget {
  final String userEmail;
  final LatLng? near;

  const CommunityPathsScreen({super.key, required this.userEmail, this.near});

  @override
  State<CommunityPathsScreen> createState() => _CommunityPathsScreenState();
}

class _CommunityPathsScreenState extends State<CommunityPathsScreen> {
  // Pending paths further away than this are not offered for review.
  static const double nearbyMeters = 25000;

  List<CommunityPath> paths = [];

  bool isLoading = true;
  String? loadError;
  String? confirmingId;

  @override
  void initState() {
    super.initState();
    loadPaths();
  }

  Future<void> loadPaths() async {
    try {
      final loaded = await PathService.loadPaths();

      if (!mounted) return;

      setState(() {
        paths = loaded;
        isLoading = false;
        loadError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = 'Could not load community paths.';
      });
    }
  }

  // Distance from the rider to the closer end of a path
  double? distanceTo(CommunityPath path) {
    final near = widget.near;

    if (near == null || path.points.isEmpty) return null;

    final toStart = PathService.metersBetween(near, path.points.first.point);
    final toEnd = PathService.metersBetween(near, path.points.last.point);

    return toStart < toEnd ? toStart : toEnd;
  }

  // Confirm that the rider rode this path
  Future<void> confirmPath(CommunityPath path) async {
    setState(() => confirmingId = path.id);

    CommunityPath? updated;

    try {
      updated = await PathService.confirmPath(path.id, widget.userEmail);
    } catch (_) {
      updated = null;
    }

    if (!mounted) return;

    setState(() => confirmingId = null);

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not confirm this path.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated.isVerified
              ? 'Path verified! It can now be used in routes.'
              : 'Thanks! Confirmation saved.',
        ),
      ),
    );

    await loadPaths();
  }

  // Section title
  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget emptyText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }

  // One path with its status and, if allowed, a confirm button
  Widget pathCard(CommunityPath path, {required bool canConfirm}) {
    final details = [
      PathService.formatLength(path.lengthMeters),
      if (path.durationSeconds > 0)
        '${(path.durationSeconds / 60).round()} min',
      if (path.bikeType.isNotEmpty) path.bikeType,
    ].join(' · ');

    final distance = distanceTo(path);
    final alreadyConfirmed = path.isConfirmedBy(widget.userEmail);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                path.status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: path.isVerified
                      ? const Color(0xFF087B43)
                      : const Color(0xFFB05A00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(details, style: const TextStyle(fontSize: 13)),
          if (path.description.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              path.description.trim(),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            [
              'Confirmations: ${path.confirmations.length}/${PathService.confirmationsToVerify}',
              if (distance != null)
                '${PathService.formatLength(distance)} away',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (canConfirm) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: alreadyConfirmed || confirmingId != null
                    ? null
                    : () => confirmPath(path),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAF3EE),
                  foregroundColor: const Color(0xFF087B43),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(
                  alreadyConfirmed ? Icons.check : Icons.directions_bike,
                ),
                label: Text(alreadyConfirmed ? 'Confirmed' : 'I rode this'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = paths
        .where((path) => path.isSubmittedBy(widget.userEmail))
        .toList();

    final toReview = paths.where((path) {
      if (!path.isPending || path.isSubmittedBy(widget.userEmail)) {
        return false;
      }
      final distance = distanceTo(path);
      return distance == null || distance <= nearbyMeters;
    }).toList();

    if (widget.near != null) {
      toReview.sort(
        (a, b) => (distanceTo(a) ?? 0).compareTo(distanceTo(b) ?? 0),
      );
    }

    final verified = paths
        .where(
          (path) => path.isVerified && !path.isSubmittedBy(widget.userEmail),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Community paths')),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : loadError != null
            ? Center(child: Text(loadError!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  sectionTitle('Paths to review'),
                  if (toReview.isEmpty)
                    emptyText(
                      widget.near == null
                          ? 'No pending paths from other riders.'
                          : 'No pending paths from other riders nearby.',
                    ),
                  for (final path in toReview)
                    pathCard(path, canConfirm: true),

                  sectionTitle('Your submissions'),
                  if (mine.isEmpty)
                    emptyText('You have not submitted a path yet.'),
                  for (final path in mine) pathCard(path, canConfirm: false),

                  if (verified.isNotEmpty) ...[
                    sectionTitle('Verified paths'),
                    for (final path in verified)
                      pathCard(path, canConfirm: false),
                  ],
                ],
              ),
      ),
    );
  }
}

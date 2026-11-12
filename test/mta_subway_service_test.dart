import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:bike_nav/screens/mta_subway_service.dart';

void main() {
  test('parses active subway schedules and station data from GTFS', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'stops.txt',
          'stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station\n'
              'A,"Alpha, Park",40.0,-74.0,1,\n'
              'A1,"Alpha, Park",40.0,-74.0,,A\n'
              'B,Bravo,40.01,-74.0,1,\n'
              'B1,Bravo,40.01,-74.0,,B\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'routes.txt',
          'route_id,route_short_name\n'
              'R1,1\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'trips.txt',
          'route_id,service_id,trip_id,trip_headsign,shape_id\n'
              'R1,weekday,T1,Bravo,SH1\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'shapes.txt',
          'shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n'
              'SH1,40.0,-74.0,1\n'
              'SH1,40.005,-74.005,2\n'
              'SH1,40.01,-74.0,3\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'calendar.txt',
          'service_id,monday,tuesday,wednesday,thursday,friday,saturday,'
              'sunday,start_date,end_date\n'
              'weekday,1,1,1,1,1,0,0,20261101,20261130\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'calendar_dates.txt',
          'service_id,date,exception_type\n',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'stop_times.txt',
          'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
              'T1,09:59:00,10:00:00,A1,1\n'
              'T1,10:09:00,10:10:00,B1,2\n',
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final data = await MtaSubwayService.parseArchiveBytes(
      bytes,
      now: DateTime(2026, 11, 11, 9, 50),
    );

    expect(data.stations, hasLength(2));
    expect(data.stations.first.name, 'Alpha, Park');
    expect(data.stations.first.routes, ['1']);
    expect(data.trips, hasLength(1));
    expect(
      data
          .nextDepartures(
            'A',
            after: DateTime(2026, 11, 11, 9, 50),
            route: '1',
            headsign: 'Bravo',
          )
          .single
          .departure,
      DateTime(2026, 11, 11, 10),
    );
    final journey = data.findJourney(
      startStationId: 'A',
      endStationId: 'B',
      after: DateTime(2026, 11, 11, 9, 50),
    )!;
    expect(journey.single.route, '1');
    expect(journey.single.pathPoints, [
      const LatLng(40.0, -74.0),
      const LatLng(40.005, -74.005),
      const LatLng(40.01, -74.0),
    ]);
  });
}

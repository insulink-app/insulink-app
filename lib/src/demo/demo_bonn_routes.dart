import 'package:insulink/src/demo/demo_route.dart';

/// The demo trainings' routes along real paths in Bonn. Waypoints are
/// (latitude, longitude) placed along the OpenStreetMap geometry of the named
/// streets and banks, about 25 m inland of the Rhine; every smoothed point was
/// checked against the river polygon, so no route runs through the water except
/// on the two bridges. [DemoRoute] smooths the path between them.
class DemoBonnRoutes {
  /// A loop through the Rheinaue park on the south bank, out towards the river and back.
  static final rheinaue = DemoRoute(const [
    (50.7138, 7.1425),
    (50.7122, 7.1438),
    (50.7104, 7.1440),
    (50.7080, 7.1462),
    (50.7062, 7.1500),
    (50.7078, 7.1530),
    (50.7102, 7.1500),
    (50.7120, 7.1478),
    (50.7136, 7.1460),
    (50.7146, 7.1446),
  ]);

  /// From the Alter Zoll south along the Rhine promenade (Brasserts-, Rathenau-,
  /// Wilhelm-Spiritus- and Stresemannufer), back up the Adenauerallee.
  static final riverside = DemoRoute(const [
    (50.7348, 7.1078),
    (50.7340, 7.1082),
    (50.7310, 7.1094),
    (50.7280, 7.1116),
    (50.7250, 7.1151),
    (50.7220, 7.1199),
    (50.7200, 7.1253),
    (50.7190, 7.1284),
    (50.7198, 7.1230),
    (50.7207, 7.1170),
    (50.7232, 7.1134),
    (50.7252, 7.1119),
    (50.7284, 7.1097),
    (50.7307, 7.1080),
    (50.7330, 7.1070),
  ]);

  /// Up the west bank, over the Konrad-Adenauer-Brücke, down the Beuel side
  /// (Rheinufer Beuel-Süd, Johannes-Bücher-Ufer) and back over the Kennedybrücke.
  static final bridges = DemoRoute(const [
    (50.7348, 7.1078),
    (50.7310, 7.1094),
    (50.7280, 7.1116),
    (50.7250, 7.1151),
    (50.7220, 7.1199),
    (50.7200, 7.1253),
    (50.7186, 7.1300),
    (50.7176, 7.1345),
    (50.7165, 7.1385),
    (50.7156, 7.1414),
    (50.7178, 7.1434),
    (50.7200, 7.1449),
    (50.7222, 7.1420),
    (50.7235, 7.1360),
    (50.7246, 7.1300),
    (50.7258, 7.1258),
    (50.7284, 7.1205),
    (50.7310, 7.1170),
    (50.7334, 7.1153),
    (50.7362, 7.1145),
    (50.7385, 7.1146),
    (50.7381, 7.1110),
    (50.7377, 7.1072),
    (50.7356, 7.1076),
  ]);

  /// Hofgarten, down the Poppelsdorfer Allee to the palace and back up the
  /// other carriageway.
  static final poppelsdorf = DemoRoute(const [
    (50.7335, 7.1030),
    (50.7322, 7.1010),
    (50.7311, 7.0996),
    (50.7300, 7.0989),
    (50.7290, 7.0977),
    (50.7278, 7.0961),
    (50.7266, 7.0945),
    (50.7261, 7.0930),
    (50.7268, 7.0937),
    (50.7282, 7.0956),
    (50.7296, 7.0972),
    (50.7308, 7.0989),
    (50.7318, 7.1008),
    (50.7329, 7.1036),
  ]);
}

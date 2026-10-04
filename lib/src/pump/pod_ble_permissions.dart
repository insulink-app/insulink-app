import 'package:insulink/src/demo/demo_mode.dart';
import 'package:permission_handler/permission_handler.dart';

/// The Bluetooth permissions a pod scan and connect need.
///
/// Requested from the UI isolate before an activation, because that isolate is
/// the only one that can show a dialog — and because a pump user who has never
/// set up a CGM sensor has never been asked for them. Without this the very first
/// pod scan fails with a platform error that says nothing useful, at the exact
/// moment a pod has been filled and is waiting.
///
/// Mirrors `CgmController._ensureBlePermissions`, including its fallback: Android
/// 12+ wants scan and connect, older versions grant those implicitly and want
/// location instead. The browser demo talks to the in-memory demo pod and has no
/// radio to ask for.
class PodBlePermissions {
  const PodBlePermissions();

  Future<bool> ensure() async {
    if (DemoMode.enabled) {
      return true;
    }
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted =
        statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final locationGranted =
        statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    return (scanGranted && connectGranted) || locationGranted;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:insulink/src/auth/permissions/permission_step.dart';
import 'package:insulink/src/cgm/service/alarms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One explained permission the user is walked through before sign-in.
typedef PermissionRequest = ({
  IconData icon,
  String titleKey,
  String bodyKey,
  Future<void> Function() request,
});

/// Page-by-page permission flow shown on first launch. Each page explains why a
/// permission is needed and requests it; the last page finishes via [onDone].
/// The hard enforcement still happens when the BLE service starts — this is the
/// up-front explanation Android's bare system dialogs lack.
class PermissionOnboarding extends StatefulWidget {
  const PermissionOnboarding({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  State<PermissionOnboarding> createState() => _PermissionOnboardingState();
}

class _PermissionOnboardingState extends State<PermissionOnboarding> {
  final _controller = PageController();
  int _index = 0;
  bool _busy = false;

  static final List<PermissionRequest> _permissions = [
    (
      icon: PhosphorIconsBold.bluetooth,
      titleKey: 'permission.bluetooth.title',
      bodyKey: 'permission.bluetooth.body',
      request: () async {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
      },
    ),
    (
      icon: PhosphorIconsFill.bellRinging,
      titleKey: 'permission.notification.title',
      bodyKey: 'permission.notification.body',
      request: () async {
        await Permission.notification.request();
      },
    ),
    (
      icon: PhosphorIconsBold.prohibit,
      titleKey: 'permission.dnd.title',
      bodyKey: 'permission.dnd.body',
      request: () async {
        await G7AlarmManager(
          FlutterLocalNotificationsPlugin(),
        ).ensureDndAccess();
      },
    ),
    (
      icon: PhosphorIconsBold.personSimpleWalk,
      titleKey: 'permission.activity.title',
      bodyKey: 'permission.activity.body',
      request: () async {
        await Permission.activityRecognition.request();
      },
    ),
    (
      icon: PhosphorIconsBold.batteryCharging,
      titleKey: 'permission.battery.title',
      bodyKey: 'permission.battery.body',
      request: () async {
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      },
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    setState(() => _busy = true);
    await _permissions[_index].request();
    if (!mounted) {
      return;
    }
    if (_index == _permissions.length - 1) {
      await widget.onDone();
      return;
    }
    // Reset BEFORE animating so the incoming page never inherits the spinner
    // (onPageChanged flips _index mid-animation, which would flash it there).
    setState(() => _busy = false);
    await _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView.builder(
          controller: _controller,
          onPageChanged: (page) => setState(() => _index = page),
          itemCount: _permissions.length,
          itemBuilder: (context, index) => PermissionStep(
            permission: _permissions[index],
            isLast: index == _permissions.length - 1,
            position: index,
            count: _permissions.length,
            busy: _busy && index == _index,
            onAllow: _advance,
          ),
        ),
      ),
    );
  }
}

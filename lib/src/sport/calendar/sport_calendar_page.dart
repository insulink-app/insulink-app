import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_section.dart';

/// Full-screen calendar of past sport activities (routines + trainings),
/// reachable from the calendar icon in the Trainings header.
class SportCalendarPage extends StatelessWidget {
  const SportCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(Locales.string(context, 'sport.calendar')),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: const [SportCalendarSection()],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/sport/activity/activity_summary_card.dart';
import 'package:insulink/src/sport/activity/sport_activity_state.dart';
import 'package:insulink/src/sport/routines/routines_section.dart';
import 'package:insulink/src/sport/training/cardio_section.dart';
import 'package:provider/provider.dart';

class SportBody extends AppPageBody {
  SportBody({super.key})
    : super(
        name: "sport.label",
        unselectedIcon: CupertinoIcons.sportscourt,
        selectedIcon: CupertinoIcons.sportscourt_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const SportBodyContent();
  }
}

/// Sport-Startseite. Eigene Sektionen (Heute, Gewicht); Routinen + Statistik
/// folgen in Phase 2/3. Eigenes Widget, damit der Schrittzähler beim ersten
/// Öffnen gestartet werden kann.
class SportBodyContent extends StatefulWidget {
  const SportBodyContent({super.key});

  @override
  State<SportBodyContent> createState() => _SportBodyContentState();
}

class _SportBodyContentState extends State<SportBodyContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SportActivityState>().ensureStarted();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Immer scroll-/bouncefähig, damit die ganze Seite einheitlich als ein
      // Block mitscrollt (kein „festgeklebter" Abschnitt).
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      // Bottom-Padding hält die zentrierte Injection-FAB (page.dart) frei.
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: const [
        ActivitySummaryCard(),
        SizedBox(height: 28),
        CardioSection(),
        SizedBox(height: 28),
        RoutinesSection(),
      ],
    );
  }
}

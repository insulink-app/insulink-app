import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Sub-page for one profile topic: its title in the app bar and the topic's
/// settings widgets in a scrollable body. The overview ([ProfilePage]) pushes
/// this when a topic row is tapped.
class ProfileTopicPage extends StatelessWidget {
  const ProfileTopicPage({
    super.key,
    required this.titleKey,
    required this.children,
  });

  final String titleKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(titleKey),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: children,
      ),
    );
  }
}

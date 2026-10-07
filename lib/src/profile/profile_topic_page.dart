import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Sub-page for one profile topic: its title in the app bar and the topic's
/// settings widgets in a scrollable body. The overview ([ProfilePage]) pushes
/// this when a topic row is tapped.
///
/// The body always fills at least the viewport (and scrolls beyond it), so a
/// topic can push trailing content to the bottom of the page with a [Spacer].
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
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              InkSpace.panelMargin,
              16,
              InkSpace.panelMargin,
              40,
            ),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

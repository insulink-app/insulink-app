import 'package:flutter/material.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/account/profile_account_box.dart';
import 'package:insulink/src/profile/profile_settings.dart';
import 'package:insulink/src/profile/profile_topic_page.dart';
import 'package:insulink/src/profile/profile_topics.dart';
import 'package:insulink/src/trash/trash_list.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _search = TextEditingController();
  String _query = "";

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ProfileTopic topic) {
    if (_query.isEmpty) {
      return true;
    }
    final corpus =
        '${Locales.string(context, topic.titleKey)} '
                '${Locales.string(context, topic.searchKey)}'
            .toLowerCase();
    return corpus.contains(_query);
  }

  /// Pushes the latest settings to the backend, then leaves the page. Funnels
  /// both the app-bar arrow and the system back gesture so a change always
  /// syncs. The push is fire-and-forget — leaving must never wait on the network.
  void _leave() {
    ProfileSettings().push(Navigator.of(context, rootNavigator: true).context);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.isNotEmpty;
    final visible = const ProfileTopicCatalog().all.where(_matches).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(PhosphorIconsBold.arrowLeft),
            onPressed: _leave,
          ),
          title: LocaleText("profile.label"),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash),
              tooltip: Locales.string(context, "profile.trash"),
              onPressed: () =>
                  _open("profile.trash", () => const [TrashList()]),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            InkSpace.panelMargin,
            12,
            InkSpace.panelMargin,
            40,
          ),
          children: [
            _searchField(),
            const SizedBox(height: 16),
            if (!searching) ...[
              const ProfileAccountBox(),
              for (final group in const ProfileTopicCatalog().groups)
                ..._groupPanel(group.titleKey, group.topics),
            ],
            if (searching && visible.isNotEmpty) _topicPanel(visible),
            if (searching && visible.isEmpty) _noResults(),
            if (!searching) _footer(),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: Locales.string(context, "profile.search"),
        fillColor: context.ink.panel,
        prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(PhosphorIconsBold.x),
                onPressed: _search.clear,
              ),
      ),
    );
  }

  /// A group of the overview: its header, then its topics in one panel.
  List<Widget> _groupPanel(String titleKey, List<ProfileTopic> topics) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SectionHeader(titleKey: titleKey),
      ),
      _topicPanel(topics),
    ];
  }

  Widget _topicPanel(List<ProfileTopic> topics) {
    return InkPanel.list(
      radius: InkRadius.tile,
      rows: [for (final topic in topics) _topicRow(topic)],
    );
  }

  /// One settings row of the panel: icon disc, title and a chevron to its
  /// sub-page.
  Widget _topicRow(ProfileTopic topic) {
    return ListRow(
      icon: topic.icon,
      title: Locales.string(context, topic.titleKey),
      trailing: Icon(
        PhosphorIconsBold.caretRight,
        size: 18,
        color: context.ink.muted,
      ),
      onTap: () => _open(topic.titleKey, topic.children),
    );
  }

  /// Pushes the [ProfileTopicPage] titled [titleKey] with the given settings.
  void _open(String titleKey, List<Widget> Function() children) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProfileTopicPage(titleKey: titleKey, children: children()),
      ),
    );
  }

  Widget _noResults() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(child: LocaleText("profile.search.empty")),
    );
  }

  Widget _footer() {
    return Column(children: [const SizedBox(height: 30), _version()]);
  }

  Widget _version() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => Text(
        Locales.string(
          context,
          "profile.version",
          params: [snapshot.data?.version ?? ""],
        ),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

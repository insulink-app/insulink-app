import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/glucose_share/glucose_share.dart';
import 'package:insulink/src/glucose_share/glucose_share_row.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Profile topic for the glucose share links: a name for whom the next link is,
/// and the links given out so far, each to copy or delete. What a link shows
/// is said above them; the links live on the account, not on the phone.
class GlucoseShareSection extends StatefulWidget {
  const GlucoseShareSection({super.key});

  @override
  State<GlucoseShareSection> createState() => _GlucoseShareSectionState();
}

class _GlucoseShareSectionState extends State<GlucoseShareSection> {
  final _client = const GlucoseShareClient();
  final _name = TextEditingController();
  List<GlucoseShare>? _shares;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final shares = await _client.find();
    if (mounted) {
      setState(() {
        _shares = shares;
        _loaded = true;
      });
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    _name.clear();
    await _client.create(name);
    await _reload();
  }

  Future<void> _delete(GlucoseShare share) async {
    await _client.delete(share);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LocaleText(
          'profile.share.intro',
          style: InkText.label.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 16),
        _createRow(context),
        const SizedBox(height: 16),
        _list(colors),
      ],
    );
  }

  Widget _createRow(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: TextField(
            controller: _name,
            maxLength: 64,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              counterText: '',
              hintText: Locales.string(context, 'profile.share.name_hint'),
            ),
          ),
        ),
        FilledButton(
          onPressed: _create,
          child: LocaleText('profile.share.create'),
        ),
      ],
    );
  }

  Widget _list(InsulinkColors colors) {
    final shares = _shares;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shares == null || shares.isEmpty) {
      return LocaleText(
        shares == null ? 'profile.share.unavailable' : 'profile.share.none',
        style: InkText.label.copyWith(color: colors.muted),
      );
    }
    return InkPanel.list(
      rows: [
        for (final share in shares)
          GlucoseShareRow(share: share, onDelete: () => _delete(share)),
      ],
    );
  }
}

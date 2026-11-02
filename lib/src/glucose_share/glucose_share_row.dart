import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/confirm_delete.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/glucose_share/glucose_share.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One share link: whom it is for and since when, a copy button that turns
/// into a tick for two seconds, and delete behind a confirmation.
class GlucoseShareRow extends StatefulWidget {
  const GlucoseShareRow({
    super.key,
    required this.share,
    required this.onDelete,
  });

  final GlucoseShare share;
  final VoidCallback onDelete;

  @override
  State<GlucoseShareRow> createState() => _GlucoseShareRowState();
}

class _GlucoseShareRowState extends State<GlucoseShareRow> {
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.share.url));
    _copiedTimer?.cancel();
    setState(() {
      _copiedTimer = Timer(
        const Duration(seconds: 2),
        () => setState(() => _copiedTimer = null),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final created = DateFormat('dd.MM.yyyy').format(widget.share.createdAt);
    return ListRow(
      icon: PhosphorIconsBold.link,
      title: widget.share.name,
      subtitle: Locales.string(
        context,
        'profile.share.created',
        params: [created],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: Locales.string(context, 'profile.share.copy'),
            icon: Icon(
              _copiedTimer == null
                  ? PhosphorIconsBold.copy
                  : PhosphorIconsBold.check,
            ),
            onPressed: _copy,
          ),
          IconButton(
            tooltip: Locales.string(context, 'profile.share.delete'),
            icon: const Icon(PhosphorIconsBold.trash),
            onPressed: () => confirmDelete(
              context,
              messageKey: 'profile.share.delete_confirm',
              onConfirm: widget.onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

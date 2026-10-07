import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/connections/history/device_history_active_card.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/connections/history/device_history.dart';
import 'package:insulink/src/connections/history/device_history_row.dart';
import 'package:insulink/src/connections/history/device_history_sync.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The icon in a device page header that opens that device's log.
class DeviceHistoryButton extends StatelessWidget {
  const DeviceHistoryButton({super.key, required this.kind});

  final DeviceHistoryKind kind;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeviceHistoryPage(kind: kind)),
      ),
      tooltip: Locales.string(context, kind.titleKey),
      icon: const Icon(PhosphorIconsBold.clockCounterClockwise, size: 22),
    );
  }
}

/// Every sensor, or every pod, the account has held: which one it was, when it
/// ran, and how long it was actually worn.
///
/// Read from the account rather than from the phone, because that is where the
/// log already is (see [DeviceHistorySync]) — and because it therefore survives
/// a reinstall, which is exactly when a device history is worth having.
class DeviceHistoryPage extends StatefulWidget {
  const DeviceHistoryPage({super.key, required this.kind});

  final DeviceHistoryKind kind;

  @override
  State<DeviceHistoryPage> createState() => _DeviceHistoryPageState();
}

class _DeviceHistoryPageState extends State<DeviceHistoryPage> {
  List<DeviceHistoryEntry>? _entries;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// A failed request leaves [_entries] null, which the body reports as a
  /// failure rather than as an empty log: "you have never worn a sensor" and "we
  /// could not ask" are not the same answer.
  Future<void> _load() async {
    final records = await const DeviceHistorySync().fetch(widget.kind, context);
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = records == null ? null : DeviceHistory(records).resolve();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(widget.kind.titleKey),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _entries;
    if (entries == null) {
      return _notice('connections.history.failed');
    }
    if (entries.isEmpty) {
      return _notice('connections.history.empty');
    }
    final active = entries.where((entry) => entry.isActive).toList();
    final earlier = entries.where((entry) => !entry.isActive).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          InkSpace.panelMargin,
          16,
          InkSpace.panelMargin,
          24,
        ),
        children: [
          for (final entry in active)
            Padding(
              padding: const EdgeInsets.only(bottom: InkSpace.tileGap),
              child: DeviceHistoryActiveCard(entry: entry, icon: _icon),
            ),
          if (earlier.isNotEmpty) ...[
            _earlierHeader(earlier.length, topGap: active.isEmpty ? 0 : 18),
            InkPanel.list(
              radius: InkRadius.tile,
              rows: [
                for (final entry in earlier) DeviceHistoryRow(entry: entry),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData get _icon => widget.kind == DeviceHistoryKind.sensors
      ? PhosphorIconsBold.drop
      : PhosphorIconsBold.syringe;

  /// "Frühere Sensoren" / "Frühere Pods" with their count on the right.
  Widget _earlierHeader(int count, {required double topGap}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topGap, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: LocaleText(
              widget.kind == DeviceHistoryKind.sensors
                  ? 'connections.history.earlier_sensors'
                  : 'connections.history.earlier_pumps',
              style: InkText.section,
            ),
          ),
          Text(
            '$count',
            style: InkText.label.copyWith(color: context.ink.muted),
          ),
        ],
      ),
    );
  }

  Widget _notice(String titleKey) {
    return Center(
      child: EmptyState(
        icon: PhosphorIconsBold.clockCounterClockwise,
        titleKey: titleKey,
      ),
    );
  }
}

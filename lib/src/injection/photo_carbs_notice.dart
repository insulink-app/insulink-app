import 'package:flutter/material.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/injection/photo_estimate_item.dart';
import 'package:insulink/src/injection/photo_food_row.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Lists under the carbs field the foods the photo estimate saw, most
/// carbohydrates first ([PhotoEstimate.major]). The small ones sit folded in a
/// "Sonstiges" row ([PhotoEstimate.minor]) that opens on a tap, so butter or a
/// garnish is there to check without crowding the foods that set the dose.
class PhotoCarbsNotice extends StatefulWidget {
  const PhotoCarbsNotice({
    super.key,
    required this.estimate,
    required this.onRecount,
  });

  final PhotoEstimate estimate;
  final void Function(PhotoEstimateItem item, int count) onRecount;

  @override
  State<PhotoCarbsNotice> createState() => _PhotoCarbsNoticeState();
}

class _PhotoCarbsNoticeState extends State<PhotoCarbsNotice> {
  bool _otherOpen = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final minor = widget.estimate.minor;
    final rows = [
      for (final item in widget.estimate.major)
        PhotoFoodRow(item: item, onRecount: widget.onRecount),
      if (minor.isNotEmpty) _other(context, minor),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.border),
            row,
          ],
        ],
      ),
    );
  }

  /// "Sonstiges" with its summed weight and carbs and a chevron; open, the
  /// small foods follow indented, each with its own counter when counted.
  Widget _other(BuildContext context, List<PhotoEstimateItem> minor) {
    final colors = context.ink;
    final combined = PhotoEstimateItem.combined(
      Locales.string(context, 'injection.photo.other'),
      minor,
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(InkRadius.field),
            onTap: () => setState(() => _otherOpen = !_otherOpen),
            child: PhotoFoodRow(
              item: combined,
              onRecount: widget.onRecount,
              trailing: AnimatedRotation(
                turns: _otherOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  PhosphorIconsBold.caretDown,
                  size: 18,
                  color: colors.muted,
                  semanticLabel: Locales.string(
                    context,
                    _otherOpen
                        ? 'injection.photo.other_close'
                        : 'injection.photo.other_open',
                  ),
                ),
              ),
            ),
          ),
          if (_otherOpen)
            for (final item in minor)
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: PhotoFoodRow(item: item, onRecount: widget.onRecount),
              ),
        ],
      ),
    );
  }
}

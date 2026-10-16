import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/alert/loader_alert.dart';
import 'package:insulink/src/injection/photo_estimate.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The camera button in the top right corner of the bolus calculator's carbs
/// card.
///
/// Takes a meal photo, scaled to 1024 px and JPEG-compressed (what the server
/// estimates and keeps), and reports the estimate through [onEstimate]. A
/// failed estimate or one that saw no food is said in a dialog and reports
/// nothing, so the field keeps whatever the user had typed.
class PhotoCarbsButton extends StatelessWidget {
  const PhotoCarbsButton({super.key, required this.onEstimate});

  final void Function(PhotoEstimate estimate) onEstimate;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: Locales.string(context, 'injection.photo.take'),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(PhosphorIconsBold.camera, size: 22),
      onPressed: () => _photograph(context),
    );
  }

  Future<void> _photograph(BuildContext context) async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );
    if (photo == null || !context.mounted) {
      return;
    }
    final estimate = await _estimateWithLoader(context, photo);
    if (!context.mounted) {
      return;
    }
    if (estimate == null || !estimate.hasFood) {
      _sayNoEstimate(context, estimate);
      return;
    }
    onEstimate(estimate);
  }

  /// The estimate behind the spinner card, which goes away either way.
  Future<PhotoEstimate?> _estimateWithLoader(
    BuildContext context,
    XFile photo,
  ) async {
    const LoaderAlert().show(context);
    final jpeg = await photo.readAsBytes();
    final estimate = context.mounted
        ? await PhotoEstimate.request(context, jpeg)
        : null;
    if (context.mounted) {
      Navigator.pop(context);
    }
    return estimate;
  }

  /// Failed outright, or answered but found nothing to eat on the photo.
  void _sayNoEstimate(BuildContext context, PhotoEstimate? estimate) {
    Alert(
      type: AlertType.error,
      description: estimate == null
          ? 'injection.photo.failed'
          : 'injection.photo.no_food',
    ).show(context);
  }
}

/// Says under the carbs field that its value came from a photo, by naming the
/// dish the model saw.
class PhotoCarbsNotice extends StatelessWidget {
  const PhotoCarbsNotice({super.key, required this.estimate});

  final PhotoEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Row(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.camera, size: 16, color: colors.muted),
          Expanded(
            child: Text(
              estimate.name,
              style: InkText.label.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

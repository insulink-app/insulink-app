import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:insulink/src/nutrition/meal/meal_photo_page.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The meal's photo at the top of the meal sheet, full width with rounded
/// corners; a tap opens it full screen with the same download. While it loads
/// the space is held by a quiet panel, and a photo that cannot be loaded
/// (offline) gives the space back instead of showing an error above the stats.
class MealPhotoBanner extends StatefulWidget {
  const MealPhotoBanner({super.key, required this.photoId});

  final String photoId;

  @override
  State<MealPhotoBanner> createState() => _MealPhotoBannerState();
}

class _MealPhotoBannerState extends State<MealPhotoBanner> {
  static const _height = 220.0;

  late final Future<Uint8List?> _photo = fetchMealPhoto(
    context,
    widget.photoId,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final photo = snapshot.data;
        if (!loading && photo == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(InkRadius.panel),
            child: SizedBox(
              height: _height,
              child: photo == null ? _placeholder() : _picture(photo),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: context.ink.ground,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  Widget _picture(Uint8List photo) {
    return Material(
      child: Ink.image(
        image: MemoryImage(photo),
        fit: BoxFit.cover,
        child: InkWell(onTap: () => openMealPhoto(context, _photo)),
      ),
    );
  }
}

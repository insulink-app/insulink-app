import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Opens the photo a meal entry was estimated from.
Future<void> openMealPhoto(BuildContext context, String photoId) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => MealPhotoPage(photoId: photoId)));
}

/// A meal photo full screen, black like the camera it came from, pinch to
/// zoom. The photo lives only on the server (`/nutrition/photos/find/`), so it
/// is fetched each time; offline it says it could not be loaded.
class MealPhotoPage extends StatefulWidget {
  const MealPhotoPage({super.key, required this.photoId});

  final String photoId;

  @override
  State<MealPhotoPage> createState() => _MealPhotoPageState();
}

class _MealPhotoPageState extends State<MealPhotoPage> {
  late final Future<Uint8List?> _photo = _load();

  Future<Uint8List?> _load() async {
    final response = await Request.post(
      url: '/nutrition/photos/find/',
      body: {'id': widget.photoId},
    ).send(context);
    final image = response?.jsonObject?['image'];
    if (response == null || !response.isApiSuccess || image is! String) {
      return null;
    }
    return base64Decode(image);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const CloseButton(),
      ),
      body: FutureBuilder<Uint8List?>(
        future: _photo,
        builder: (context, snapshot) => Center(child: _body(snapshot)),
      ),
    );
  }

  Widget _body(AsyncSnapshot<Uint8List?> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final photo = snapshot.data;
    if (photo == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: LocaleText(
          'nutrition.meals.photo_failed',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
      );
    }
    return InteractiveViewer(maxScale: 4, child: Image.memory(photo));
  }
}

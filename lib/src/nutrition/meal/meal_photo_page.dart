import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Fetches a stored meal photo from the server (`/nutrition/photos/find/`).
/// Null offline, or when the server has no such photo for this user.
Future<Uint8List?> fetchMealPhoto(BuildContext context, String photoId) async {
  final response = await Request.post(
    url: '/nutrition/photos/find/',
    body: {'id': photoId},
  ).send(context);
  final image = response?.jsonObject?['image'];
  if (response == null || !response.isApiSuccess || image is! String) {
    return null;
  }
  return base64Decode(image);
}

/// Opens a meal photo full screen. [photo] is a fetch already running (or
/// done), so a photo the meal sheet has shown is not downloaded twice.
Future<void> openMealPhoto(BuildContext context, Future<Uint8List?> photo) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => MealPhotoPage(photo: photo)));
}

/// A meal photo full screen, black like the camera it came from, pinch to
/// zoom. The photo lives only on the server, so offline it says it could not
/// be loaded.
class MealPhotoPage extends StatelessWidget {
  const MealPhotoPage({super.key, required this.photo});

  final Future<Uint8List?> photo;

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
        future: photo,
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

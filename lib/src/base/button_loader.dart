import 'package:flutter/material.dart';

/// The spinner a button shows while its action runs.
///
/// Takes its colour from the button it sits in (the icon colour every Material
/// button hands its child), so it follows the button's state: a busy button is
/// usually disabled, and a fixed `onPrimary` spinner then sat dark on the dark
/// disabled face and could not be seen.
class ButtonLoader extends StatelessWidget {
  const ButtonLoader({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: IconTheme.of(context).color,
      ),
    );
  }
}

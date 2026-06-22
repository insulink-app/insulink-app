import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/profile/profile_page.dart';

class HeaderAccountButton extends StatefulWidget
    implements PreferredSizeWidget {
  const HeaderAccountButton({super.key});

  @override
  State<HeaderAccountButton> createState() => _HeaderAccountButtonState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _HeaderAccountButtonState extends State<HeaderAccountButton> {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(CupertinoIcons.person_crop_circle_fill, size: 40),
      color: const Color(0xFFB3B3B3),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ProfilePage()),
        );
      },
    );
  }
}

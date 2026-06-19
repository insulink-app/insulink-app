import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class InjectionButton extends StatefulWidget {
  const InjectionButton({super.key});

  @override
  State<InjectionButton> createState() => _InjectionButtonState();
}

class _InjectionButtonState extends State<InjectionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    var color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double glowValue = sin(_controller.value * pi);
        return Container(
          height: 70,
          width: 70,
          margin: EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).appBarTheme.backgroundColor!,
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6 * min(glowValue + 0.5, 1)),
                blurRadius: 15 * (glowValue + 0.5),
                spreadRadius: 4 * (glowValue + 0.5),
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () {
              /*Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InjectionCreatePage(
                    recipients: [],
                  ),
                ),
              );*/
            },
            backgroundColor:
                Color.lerp(color.withValues(alpha: 0.9), color, glowValue),
            shape: CircleBorder(),
            child: Icon(CupertinoIcons.eyedropper, size: 35, color: Colors.white),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

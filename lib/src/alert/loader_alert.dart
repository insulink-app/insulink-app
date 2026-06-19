import 'package:flutter/material.dart';

class LoaderAlert extends StatefulWidget {
  const LoaderAlert({super.key});

  @override
  State<LoaderAlert> createState() => _LoaderAlertState();

  show(context) {
    showDialog(context: context, builder: (BuildContext context) => this);
  }
}

class _LoaderAlertState extends State<LoaderAlert> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(15.0)),
      ),
      content: SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.onSurface,
              strokeWidth: 4,
            ),
          ),
        ),
      ),
    );
  }
}

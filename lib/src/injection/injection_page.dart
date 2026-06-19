import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class InjectionPage extends StatefulWidget {
  const InjectionPage({super.key});

  @override
  State<InjectionPage> createState() => _InjectionPageState();
}

class _InjectionPageState extends State<InjectionPage>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(CupertinoIcons.arrow_left),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SizedBox.shrink(),
    );
  }
}

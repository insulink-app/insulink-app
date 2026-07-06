import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locale_text.dart';

/// Placeholder nutrition tab — content lands here later.
class NutritionBody extends AppPageBody {
  NutritionBody({super.key})
    : super(
        name: "nutrition.label",
        unselectedIcon: CupertinoIcons.cart,
        selectedIcon: CupertinoIcons.cart_fill,
      );

  @override
  Widget content(BuildContext context) {
    return Center(
      child: LocaleText(
        'nutrition.placeholder',
        style: TextStyle(fontSize: 15, color: Colors.grey[500]),
      ),
    );
  }
}

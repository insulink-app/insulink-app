import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/base/segment_bar.dart';

void main() {
  testWidgets('every segment fills the bar height', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            child: SegmentBar.count(
              total: 10,
              filled: 6,
              fill: const Color(0xFF0000FF),
              empty: const Color(0xFFCCCCCC),
            ),
          ),
        ),
      ),
    );
    final pieces = find.byType(DecoratedBox);
    expect(pieces, findsNWidgets(10));
    expect(tester.getSize(pieces.first).height, 6);
  });
}

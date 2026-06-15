// Flutter widget and painter integration tests for BonyPainter / BonyWidget.
// Run with: flutter test test/flutter/bony_painter_test.dart
//
// Uses the m2_rig.bony conformance asset, consumed via buildDrawBatches, and
// renders via BonyPainter to verify no exceptions are thrown during painting.

import 'dart:io';

import 'package:bony/bony.dart';
import 'package:bony/flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<DrawBatch> batches;

  setUpAll(() {
    final data = loadBonyJson(
      File('../conformance/assets/m2_rig.bony').readAsStringSync(),
    );
    batches = buildDrawBatches(data);
  });

  group('BonyPainter', () {
    test('instantiates with empty batches', () {
      final painter = BonyPainter(batches: const []);
      expect(painter, isA<BonyPainter>());
    });

    test('instantiates with m2 batches', () {
      final painter = BonyPainter(batches: batches);
      expect(painter, isA<BonyPainter>());
    });

    test('shouldRepaint returns false for identical references', () {
      final painter = BonyPainter(batches: batches);
      expect(painter.shouldRepaint(painter), isFalse);
    });

    test('shouldRepaint returns true when batches differ', () {
      final a = BonyPainter(batches: batches);
      final b = BonyPainter(batches: List.from(batches));
      expect(a.shouldRepaint(b), isTrue);
    });

    testWidgets('renders without exception', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BonyWidget(
            batches: batches,
            size: const Size(400, 300),
          ),
        ),
      );
      // No exception means success.
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('renders empty batches without exception', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: BonyWidget(batches: [], size: Size(100, 100)),
        ),
      );
      expect(find.byType(CustomPaint), findsOneWidget);
    });
  });

  group('BonyWidget', () {
    testWidgets('builds a CustomPaint with the painter', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BonyWidget(batches: batches),
        ),
      );
      final cp = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect(cp.painter, isA<BonyPainter>());
    });

    testWidgets('passes size hint through', (tester) async {
      const hint = Size(200.0, 150.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BonyWidget(batches: batches, size: hint),
        ),
      );
      final cp = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect(cp.size, hint);
    });
  });
}

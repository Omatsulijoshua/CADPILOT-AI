import 'dart:math' as math;

import 'package:cadpilot_tablet/src/sketch_models.dart';
import 'package:cadpilot_tablet/src/sketch_recognition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const recognizer = RoughStrokeRecognizer();

  test('noisy closed circle becomes an editable dimensioned circle', () {
    final points = List.generate(65, (index) {
      final angle = math.pi * 2 * index / 64;
      final noise = index.isEven ? 1.4 : -1.0;
      return Offset(100 + (40 + noise) * math.cos(angle),
          80 + (40 - noise) * math.sin(angle));
    });
    final result = recognizer.recognize(points)!;
    expect(result.kind, SketchEntityKind.circle);
    final entity = result.toEntity('circle-1');
    expect(entity.kind, SketchEntityKind.circle);
    expect(entity.dimensionLocked, isTrue);
    expect(entity.primaryDimension, closeTo(40, 2));
    expect(entity.recognitionConfidence, inInclusiveRange(0.55, 0.99));
  });

  test('rough rectangle becomes constrained editable rectangle', () {
    final points = <Offset>[];
    for (var x = 20; x <= 120; x += 5) {
      points.add(Offset(x.toDouble(), 20 + (x % 3)));
    }
    for (var y = 25; y <= 75; y += 5) {
      points.add(Offset(120 + (y % 2), y.toDouble()));
    }
    for (var x = 115; x >= 20; x -= 5) {
      points.add(Offset(x.toDouble(), 80 + (x % 2)));
    }
    for (var y = 75; y >= 20; y -= 5) {
      points.add(Offset(20 + (y % 2), y.toDouble()));
    }
    final result = recognizer.recognize(points)!;
    expect(result.kind, SketchEntityKind.rectangle);
    final entity = result.toEntity('rect-1');
    expect(entity.kind, SketchEntityKind.rectangle);
    expect(entity.dimensionLocked, isTrue);
    expect(entity.secondaryDimension, greaterThan(50));
  });

  test('users can correct a mistaken detection before editable commit', () {
    const result = SketchRecognition(
        kind: SketchEntityKind.circle,
        start: Offset.zero,
        end: Offset(100, 60),
        confidence: 0.6);
    final corrected =
        result.toEntity('corrected', correctedKind: SketchEntityKind.rectangle);
    expect(corrected.kind, SketchEntityKind.rectangle);
    expect(
        SketchEntity.fromJson(corrected.toJson()).recognitionConfidence, 0.6);
  });

  test('open strokes are not converted into closed geometry', () {
    final points = List.generate(
        30, (index) => Offset(index * 5.0, 20 + index.toDouble()));
    expect(recognizer.recognize(points), isNull);
  });
}

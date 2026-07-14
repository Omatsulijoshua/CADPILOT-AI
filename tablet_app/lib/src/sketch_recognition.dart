import 'dart:math' as math;
import 'dart:ui';

import 'sketch_models.dart';

class SketchRecognition {
  const SketchRecognition(
      {required this.kind,
      required this.start,
      required this.end,
      required this.confidence});
  final SketchEntityKind kind;
  final Offset start;
  final Offset end;
  final double confidence;
  SketchEntity toEntity(String id, {SketchEntityKind? correctedKind}) {
    final kind = correctedKind ?? this.kind;
    final rect = Rect.fromPoints(start, end);
    if (kind == SketchEntityKind.circle) {
      final center = rect.center;
      final radius = (rect.width + rect.height) / 4;
      return SketchEntity(
          id: id,
          kind: kind,
          start: center,
          end: center + Offset(radius, 0),
          dimensionLocked: true,
          recognitionConfidence: confidence);
    }
    return SketchEntity(
        id: id,
        kind: SketchEntityKind.rectangle,
        start: rect.topLeft,
        end: rect.bottomRight,
        dimensionLocked: true,
        recognitionConfidence: confidence);
  }
}

class RoughStrokeRecognizer {
  const RoughStrokeRecognizer();

  SketchRecognition? recognize(List<Offset> input) {
    final points = cleanup(input);
    if (points.length < 8) return null;
    final bounds = _bounds(points);
    final diagonal =
        math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    if (bounds.width < 8 ||
        bounds.height < 8 ||
        (points.first - points.last).distance > math.max(14, diagonal * 0.22)) {
      return null;
    }
    final perimeter =
        _perimeter(points) + (points.last - points.first).distance;
    final area = _area(points).abs();
    if (perimeter <= 0 || area <= 4) return null;
    final circularity = 4 * math.pi * area / (perimeter * perimeter);
    final aspect = bounds.width / bounds.height;
    final circleScore = (1 - (1 - circularity).abs()).clamp(0.0, 1.0) *
        (1 - (aspect - 1).abs().clamp(0.0, 1.0));
    if (circularity >= 0.84 && aspect >= 0.65 && aspect <= 1.55) {
      return SketchRecognition(
          kind: SketchEntityKind.circle,
          start: bounds.topLeft,
          end: bounds.bottomRight,
          confidence: circleScore.clamp(0.55, 0.99));
    }
    final rectangleScore = (1 - (circularity - 0.72).abs()).clamp(0.0, 1.0);
    return SketchRecognition(
        kind: SketchEntityKind.rectangle,
        start: bounds.topLeft,
        end: bounds.bottomRight,
        confidence: rectangleScore.clamp(0.5, 0.96));
  }

  List<Offset> cleanup(List<Offset> input) {
    if (input.isEmpty) return const [];
    final filtered = <Offset>[input.first];
    for (final point in input.skip(1)) {
      if ((point - filtered.last).distance >= 2) filtered.add(point);
    }
    if (filtered.length < 3) return filtered;
    return List.generate(filtered.length, (index) {
      if (index == 0 || index == filtered.length - 1) return filtered[index];
      return (filtered[index - 1] + filtered[index] * 2 + filtered[index + 1]) /
          4;
    });
  }

  Rect _bounds(List<Offset> points) {
    var left = points.first.dx,
        right = left,
        top = points.first.dy,
        bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _perimeter(List<Offset> points) {
    var value = 0.0;
    for (var index = 1; index < points.length; index++) {
      value += (points[index] - points[index - 1]).distance;
    }
    return value;
  }

  double _area(List<Offset> points) {
    var value = 0.0;
    for (var index = 0; index < points.length; index++) {
      final next = points[(index + 1) % points.length];
      value += points[index].dx * next.dy - next.dx * points[index].dy;
    }
    return value / 2;
  }
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/notebook_models.dart';
import 'stroke_smoother.dart';

class StrokeTessellator {
  static Vertices? tessellateBatch(List<Stroke> strokes) {
    if (strokes.isEmpty) return null;

    final positions = <double>[];
    final colors = <int>[];

    for (final stroke in strokes) {
      final single = _tessellateRaw(stroke);
      if (single == null || single.positions.isEmpty) continue;

      if (positions.isNotEmpty) {
        final lastX = positions[positions.length - 2];
        final lastY = positions[positions.length - 1];
        final lastColor = colors.last;

        final firstX = single.positions[0];
        final firstY = single.positions[1];
        final firstColor = single.colors[0];

        positions.addAll([lastX, lastY, firstX, firstY]);
        colors.addAll([lastColor, firstColor]);
      }

      positions.addAll(single.positions);
      colors.addAll(single.colors);
    }

    if (positions.isEmpty) return null;

    return Vertices.raw(
      VertexMode.triangleStrip,
      Float32List.fromList(positions),
      colors: Int32List.fromList(colors),
    );
  }

  static Vertices? tessellateSingle(Stroke stroke) {
    final raw = _tessellateRaw(stroke);
    if (raw == null || raw.positions.isEmpty) return null;

    return Vertices.raw(
      VertexMode.triangleStrip,
      Float32List.fromList(raw.positions),
      colors: Int32List.fromList(raw.colors),
    );
  }

  static _RawStrip? _tessellateRaw(Stroke stroke) {
    final points = StrokeSmoother.smooth(stroke.points, targetSegmentLength: 3.0);
    if (points.isEmpty) return null;

    final baseRadius = stroke.lineWidth * 0.5;
    final isHighlighter = stroke.toolType.toLowerCase() == 'highlighter';
    final supportsTilt = !isHighlighter;
    final baseColor = _parseHexColor(
      stroke.colorHex,
      alphaOverride: isHighlighter ? 0.35 : 1.0,
    );

    final pos = <double>[];
    final cols = <int>[];

    if (points.length == 1) {
      final p = points.first;
      final tilt = supportsTilt ? _normalizedTilt(p.altitude) : 0.0;
      final r = _effectiveRadius(
        base: baseRadius,
        pressure: p.pressure,
        tilt: tilt,
        alignment: 1.0,
        isHighlighter: isHighlighter,
      );
      final argb = _shadedColor(baseColor, tilt).toARGB32();
      const segments = 10;
      for (int i = 0; i <= segments; i++) {
        final angle = (i / segments) * 2.0 * math.pi;
        pos.addAll([p.x + math.cos(angle) * r, p.y + math.sin(angle) * r]);
        cols.add(argb);
        pos.addAll([p.x, p.y]);
        cols.add(argb);
      }
      return _RawStrip(pos, cols);
    }

    final t0 = _safeNormalize(
      points[1].x - points[0].x,
      points[1].y - points[0].y,
      1.0,
      0.0,
    );
    final n0 = Offset(-t0.dy, t0.dx);
    final tilt0 = supportsTilt ? _normalizedTilt(points[0].altitude) : 0.0;
    final align0 = _azimuthAlignment(n0, points[0].azimuth);
    final r0 = _effectiveRadius(
      base: baseRadius,
      pressure: points[0].pressure,
      tilt: tilt0,
      alignment: align0,
      isHighlighter: isHighlighter,
    );
    final argb0 = _shadedColor(baseColor, tilt0).toARGB32();

    const capSteps = 5;
    final baseStartAngle = math.atan2(n0.dy, n0.dx);
    for (int k = 0; k <= capSteps; k++) {
      final theta = baseStartAngle + (k / capSteps) * math.pi;
      pos.addAll([
        points[0].x + math.cos(theta) * r0,
        points[0].y + math.sin(theta) * r0,
      ]);
      cols.add(argb0);
      pos.addAll([points[0].x, points[0].y]);
      cols.add(argb0);
    }

    for (int i = 0; i < points.length; i++) {
      Offset normal;
      double miterScale = 1.0;

      if (i == 0) {
        normal = n0;
      } else if (i == points.length - 1) {
        final tEnd = _safeNormalize(
          points[i].x - points[i - 1].x,
          points[i].y - points[i - 1].y,
          1.0,
          0.0,
        );
        normal = Offset(-tEnd.dy, tEnd.dx);
      } else {
        final inDir = _safeNormalize(
          points[i].x - points[i - 1].x,
          points[i].y - points[i - 1].y,
          1.0,
          0.0,
        );
        final outDir = _safeNormalize(
          points[i + 1].x - points[i].x,
          points[i + 1].y - points[i].y,
          inDir.dx,
          inDir.dy,
        );
        final tangent = _safeNormalize(
          inDir.dx + outDir.dx,
          inDir.dy + outDir.dy,
          inDir.dx,
          inDir.dy,
        );
        normal = Offset(-tangent.dy, tangent.dx);

        final inNormal = Offset(-inDir.dy, inDir.dx);
        final dot = math.max(
          normal.dx * inNormal.dx + normal.dy * inNormal.dy,
          0.5,
        );
        miterScale = 1.0 / dot;
      }

      final tilt = supportsTilt ? _normalizedTilt(points[i].altitude) : 0.0;
      final alignment = _azimuthAlignment(normal, points[i].azimuth);
      final r = _effectiveRadius(
        base: baseRadius,
        pressure: points[i].pressure,
        tilt: tilt,
        alignment: alignment,
        isHighlighter: isHighlighter,
      );
      final argb = _shadedColor(baseColor, tilt).toARGB32();

      final offset = normal * (r * miterScale);
      pos.addAll([
        points[i].x + offset.dx,
        points[i].y + offset.dy,
        points[i].x - offset.dx,
        points[i].y - offset.dy,
      ]);
      cols.addAll([argb, argb]);
    }

    final last = points.length - 1;
    final tEnd = _safeNormalize(
      points[last].x - points[last - 1].x,
      points[last].y - points[last - 1].y,
      1.0,
      0.0,
    );
    final nEnd = Offset(-tEnd.dy, tEnd.dx);
    final tiltEnd = supportsTilt ? _normalizedTilt(points[last].altitude) : 0.0;
    final alignEnd = _azimuthAlignment(nEnd, points[last].azimuth);
    final rEnd = _effectiveRadius(
      base: baseRadius,
      pressure: points[last].pressure,
      tilt: tiltEnd,
      alignment: alignEnd,
      isHighlighter: isHighlighter,
    );
    final argbEnd = _shadedColor(baseColor, tiltEnd).toARGB32();

    final baseEndAngle = math.atan2(-nEnd.dy, -nEnd.dx);
    for (int k = 0; k <= capSteps; k++) {
      final theta = baseEndAngle + (k / capSteps) * math.pi;
      pos.addAll([
        points[last].x + math.cos(theta) * rEnd,
        points[last].y + math.sin(theta) * rEnd,
      ]);
      cols.add(argbEnd);
      pos.addAll([points[last].x, points[last].y]);
      cols.add(argbEnd);
    }

    return _RawStrip(pos, cols);
  }

  static double _normalizedTilt(double altitude) {
    const minAngle = 0.25;
    const threshold = 1.22;
    if (altitude >= threshold) return 0.0;
    return ((threshold - altitude) / (threshold - minAngle)).clamp(0.0, 1.0);
  }

  static double _azimuthAlignment(Offset normal, double azimuth) {
    final ax = math.cos(azimuth);
    final ay = math.sin(azimuth);
    return (normal.dx * ax + normal.dy * ay).abs();
  }

  static double _effectiveRadius({
    required double base,
    required double pressure,
    required double tilt,
    required double alignment,
    required bool isHighlighter,
  }) {
    if (isHighlighter) return base;
    final clampedPressure = pressure.clamp(0.1, 2.5);
    final pressureFactor = 0.35 + 0.65 * math.pow(clampedPressure, 0.75);
    final tiltCurve = tilt * tilt;
    final tiltExpansion = 1.0 + tiltCurve * (0.4 + 3.0 * alignment);
    return math.max(base * pressureFactor * tiltExpansion, 0.5);
  }

  static Color _shadedColor(Color base, double tilt) {
    if (tilt <= 0.0) return base;
    final alphaScale = 1.0 - (0.68 * math.pow(tilt, 1.15));
    return base.withValues(alpha: (base.a * alphaScale).clamp(0.05, 1.0));
  }

  static Offset _safeNormalize(double dx, double dy, double fbX, double fbY) {
    final len = math.sqrt((dx) * (dx) + (dy) * (dy));
    return len > 0.0001 ? Offset(dx / len, dy / len) : Offset(fbX, fbY);
  }

  static Color _parseHexColor(String hex, {required double alphaOverride}) {
    final cleaned = hex.replaceAll('#', '').trim();
    final rgb = int.tryParse(cleaned, radix: 16) ?? 0x000000;
    return Color.fromRGBO(
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
      alphaOverride,
    );
  }
}

class _RawStrip {
  final List<double> positions;
  final List<int> colors;
  _RawStrip(this.positions, this.colors);
}

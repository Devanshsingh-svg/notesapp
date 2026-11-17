import 'dart:math' as math;
import '../models/notebook_models.dart';

class StrokeSmoother {
  static List<StrokePoint> smooth(
    List<StrokePoint> points, {
    double targetSegmentLength = 3.0,
  }) {
    if (points.length < 3) return points;

    final cleaned = <StrokePoint>[points.first];
    for (int i = 1; i < points.length; i++) {
      final prev = cleaned.last;
      final curr = points[i];
      if (math.hypot(curr.x - prev.x, curr.y - prev.y) > 0.25) {
        cleaned.add(curr);
      }
    }
    if (cleaned.length < 3) return cleaned;

    final firstPhantom = _reflect(cleaned[1], across: cleaned[0]);
    final lastPhantom = _reflect(
      cleaned[cleaned.length - 2],
      across: cleaned[cleaned.length - 1],
    );

    final control = <StrokePoint>[firstPhantom, ...cleaned, lastPhantom];
    final smoothed = <StrokePoint>[cleaned.first];

    for (int i = 0; i < control.length - 3; i++) {
      final p0 = control[i];
      final p1 = control[i + 1];
      final p2 = control[i + 2];
      final p3 = control[i + 3];

      final d01 = math.hypot(p1.x - p0.x, p1.y - p0.y);
      final d12 = math.hypot(p2.x - p1.x, p2.y - p1.y);
      final d23 = math.hypot(p3.x - p2.x, p3.y - p2.y);

      final steps = (d12 / targetSegmentLength).ceil().clamp(1, 16);
      if (steps == 1) {
        smoothed.add(p2);
        continue;
      }

      const double t0 = 0.0;
      final double t1 = t0 + math.max(math.sqrt(d01), 0.0001);
      final double t2 = t1 + math.max(math.sqrt(d12), 0.0001);
      final double t3 = t2 + math.max(math.sqrt(d23), 0.0001);

      for (int step = 1; step <= steps; step++) {
        if (step == steps) {
          smoothed.add(p2);
          break;
        }

        final u = step / steps;
        final t = t1 + u * (t2 - t1);

        final a1x = ((t1 - t) / (t1 - t0)) * p0.x + ((t - t0) / (t1 - t0)) * p1.x;
        final a1y = ((t1 - t) / (t1 - t0)) * p0.y + ((t - t0) / (t1 - t0)) * p1.y;

        final a2x = ((t2 - t) / (t2 - t1)) * p1.x + ((t - t1) / (t2 - t1)) * p2.x;
        final a2y = ((t2 - t) / (t2 - t1)) * p1.y + ((t - t1) / (t2 - t1)) * p2.y;

        final a3x = ((t3 - t) / (t3 - t2)) * p2.x + ((t - t2) / (t3 - t2)) * p3.x;
        final a3y = ((t3 - t) / (t3 - t2)) * p2.y + ((t - t2) / (t3 - t2)) * p3.y;

        final b1x = ((t2 - t) / (t2 - t0)) * a1x + ((t - t0) / (t2 - t0)) * a2x;
        final b1y = ((t2 - t) / (t2 - t0)) * a1y + ((t - t0) / (t2 - t0)) * a2y;

        final b2x = ((t3 - t) / (t3 - t1)) * a2x + ((t - t1) / (t3 - t1)) * a3x;
        final b2y = ((t3 - t) / (t3 - t1)) * a2y + ((t - t1) / (t3 - t1)) * a3y;

        final cx = ((t2 - t) / (t2 - t1)) * b1x + ((t - t1) / (t2 - t1)) * b2x;
        final cy = ((t2 - t) / (t2 - t1)) * b1y + ((t - t1) / (t2 - t1)) * b2y;

        smoothed.add(StrokePoint(
          x: cx,
          y: cy,
          pressure: p1.pressure + (p2.pressure - p1.pressure) * u,
          altitude: p1.altitude + (p2.altitude - p1.altitude) * u,
          azimuth: _interpolateAngle(p1.azimuth, p2.azimuth, u),
          timestamp: p1.timestamp + (p2.timestamp - p1.timestamp) * u,
        ));
      }
    }

    return smoothed;
  }

  static StrokePoint _reflect(StrokePoint point, {required StrokePoint across}) {
    return StrokePoint(
      x: 2.0 * across.x - point.x,
      y: 2.0 * across.y - point.y,
      pressure: across.pressure,
      altitude: across.altitude,
      azimuth: across.azimuth,
      timestamp: across.timestamp,
    );
  }

  static double _interpolateAngle(double a, double b, double t) {
    final delta = math.atan2(math.sin(b - a), math.cos(b - a));
    return a + delta * t;
  }
}

import 'dart:math' as math;
import 'package:flutter/gestures.dart';

import '../models/notebook_models.dart';

enum DrawingInputMode {
  activeStylusOnly('Stylus Only'),
  universalStylus('Stylus + Touch');

  final String label;
  const DrawingInputMode(this.label);
}

class InputTouchFilter {
  DrawingInputMode inputMode = DrawingInputMode.universalStylus;
  final Set<int> _activeStylusPointers = {};

  void registerPointerDown(PointerEvent event) {
    if (_isStylus(event.kind)) {
      _activeStylusPointers.add(event.pointer);
    }
  }

  void registerPointerUpOrCancel(PointerEvent event) {
    _activeStylusPointers.remove(event.pointer);
  }

  bool shouldAcceptDrawingEvent(PointerEvent event) {
    final isStylus = _isStylus(event.kind);

    switch (inputMode) {
      case DrawingInputMode.activeStylusOnly:
        return isStylus;

      case DrawingInputMode.universalStylus:
        if (isStylus) return true;
        if (_activeStylusPointers.isNotEmpty) return false;
        if (event.radiusMajor > 18.0) return false;
        return true;
    }
  }

  bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
}

class VelocityPressureEstimator {
  Offset? _prevPos;
  Duration? _prevTime;
  double _smoothedPressure = 1.0;

  void reset() {
    _prevPos = null;
    _prevTime = null;
    _smoothedPressure = 1.0;
  }

  double effectivePressure(PointerEvent event, Offset canvasPos) {
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    if (isStylus &&
        event.pressureMax > event.pressureMin &&
        event.pressure > 0.0 &&
        event.pressure != 1.0) {
      final normalized = (event.pressure - event.pressureMin) /
          (event.pressureMax - event.pressureMin);
      return (normalized * 1.8).clamp(0.15, 2.2);
    }

    final prevPos = _prevPos;
    final prevTime = _prevTime;
    _prevPos = canvasPos;
    _prevTime = event.timeStamp;

    if (prevPos == null || prevTime == null) return 1.0;

    final dtSeconds =
        math.max((event.timeStamp - prevTime).inMicroseconds / 1e6, 0.001);
    final distance = (canvasPos - prevPos).distance;
    final velocity = distance / dtSeconds;

    final normalizedSpeed = ((velocity - 100.0) / 1700.0).clamp(0.0, 1.0);
    final targetPressure = 1.45 - (normalizedSpeed * 1.0);
    _smoothedPressure = (_smoothedPressure * 0.7) + (targetPressure * 0.3);
    return _smoothedPressure;
  }
}

class UnifiedStylusAdapter {
  static StrokePoint toStrokePoint({
    required PointerEvent event,
    required Offset canvasPos,
    required VelocityPressureEstimator pressureEstimator,
    double? simulatedTiltRadians,
  }) {
    final pressure = pressureEstimator.effectivePressure(event, canvasPos);
    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;

    double altitude = math.pi / 2;
    double azimuth = 0.0;

    if (isStylus) {
      altitude = ((math.pi / 2) - event.tilt).clamp(0.0, math.pi / 2);
      azimuth = event.orientation;
    } else if (simulatedTiltRadians != null) {
      altitude = simulatedTiltRadians;
      azimuth = math.pi / 4;
    }

    return StrokePoint(
      x: canvasPos.dx,
      y: canvasPos.dy,
      pressure: pressure,
      altitude: altitude,
      azimuth: azimuth,
      timestamp: event.timeStamp.inMicroseconds / 1e6,
    );
  }
}

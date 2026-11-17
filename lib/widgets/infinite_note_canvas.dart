import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/input_controller.dart';
import '../engine/stroke_tessellator.dart';
import '../models/notebook_models.dart';

enum CanvasToolMode {
  pen,
  pencil,
  highlighter,
  precisionEraser,
  strokeEraser,
}

class InfiniteNoteCanvas extends StatefulWidget {
  final NotePage page;
  final CanvasToolMode toolMode;
  final String selectedColorHex;
  final double lineWidth;
  final DrawingInputMode inputMode;
  final double simulatedTiltDegrees;
  final VoidCallback onHistoryChanged;
  final ValueChanged<double>? onZoomChanged;

  const InfiniteNoteCanvas({
    super.key,
    required this.page,
    required this.toolMode,
    required this.selectedColorHex,
    required this.lineWidth,
    required this.inputMode,
    required this.simulatedTiltDegrees,
    required this.onHistoryChanged,
    this.onZoomChanged,
  });

  @override
  State<InfiniteNoteCanvas> createState() => InfiniteNoteCanvasState();
}

class InfiniteNoteCanvasState extends State<InfiniteNoteCanvas> {
  final InputTouchFilter _touchFilter = InputTouchFilter();
  final VelocityPressureEstimator _pressureEstimator = VelocityPressureEstimator();

  ui.FragmentProgram? _grainProgram;
  ui.FragmentShader? _grainShader;

  Offset _cameraOffset = Offset.zero;
  double _zoom = 1.0;
  Offset _focalStart = Offset.zero;
  Offset _offsetStart = Offset.zero;
  double _zoomStart = 1.0;

  ui.Vertices? _crispCommittedVertices;
  ui.Vertices? _tiltedCommittedVertices;
  ui.Vertices? _activeVertices;

  Stroke? _currentStroke;
  Offset? _eraserCursorWorld;

  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  double get zoom => _zoom;

  @override
  void initState() {
    super.initState();
    _loadGrainShader();
    _rebuildCommittedMeshes();
  }

  @override
  void didUpdateWidget(covariant InfiniteNoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _touchFilter.inputMode = widget.inputMode;
    if (oldWidget.page.id != widget.page.id) {
      _undoStack.clear();
      _redoStack.clear();
      _currentStroke = null;
      _activeVertices = null;
      _rebuildCommittedMeshes();
    }
  }

  Future<void> _loadGrainShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/paper_grain.frag');
      if (mounted) {
        setState(() {
          _grainProgram = program;
          _grainShader = program.fragmentShader();
        });
      }
    } catch (e) {
      debugPrint('Paper grain shader fallback active: \');
    }
  }

  Offset _screenToWorld(Offset screenPos) => (screenPos - _cameraOffset) / _zoom;

  void resetZoom() {
    setState(() {
      _cameraOffset = Offset.zero;
      _zoom = 1.0;
    });
    widget.onZoomChanged?.call(1.0);
  }

  void refreshFromModel() {
    _rebuildCommittedMeshes();
    setState(() {});
  }

  void _rebuildCommittedMeshes() {
    final crispStrokes = <Stroke>[];
    final tiltedStrokes = <Stroke>[];

    for (final s in widget.page.strokes) {
      if (s.hasTiltShading) {
        tiltedStrokes.add(s);
      } else {
        crispStrokes.add(s);
      }
    }

    _crispCommittedVertices = StrokeTessellator.tessellateBatch(crispStrokes);
    _tiltedCommittedVertices = StrokeTessellator.tessellateBatch(tiltedStrokes);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List<Stroke>.from(widget.page.strokes));
    widget.page.strokes = _undoStack.removeLast();
    _rebuildCommittedMeshes();
    widget.onHistoryChanged();
    setState(() {});
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<Stroke>.from(widget.page.strokes));
    widget.page.strokes = _redoStack.removeLast();
    _rebuildCommittedMeshes();
    widget.onHistoryChanged();
    setState(() {});
  }

  void clearPage() {
    if (widget.page.strokes.isEmpty) return;
    _undoStack.add(List<Stroke>.from(widget.page.strokes));
    _redoStack.clear();
    widget.page.strokes = [];
    _rebuildCommittedMeshes();
    widget.onHistoryChanged();
    setState(() {});
  }

  void _onPointerDown(PointerDownEvent event) {
    _touchFilter.inputMode = widget.inputMode;
    _touchFilter.registerPointerDown(event);
    if (!_touchFilter.shouldAcceptDrawingEvent(event)) return;

    final worldPos = _screenToWorld(event.localPosition);

    if (widget.toolMode == CanvasToolMode.strokeEraser ||
        widget.toolMode == CanvasToolMode.precisionEraser) {
      setState(() => _eraserCursorWorld = worldPos);
      _applyEraser(worldPos);
      return;
    }

    _pressureEstimator.reset();
    final isHighlighter = widget.toolMode == CanvasToolMode.highlighter;
    final isPencil = widget.toolMode == CanvasToolMode.pencil;
    final effectiveTilt = isPencil
        ? math.min(widget.simulatedTiltDegrees, 42.0)
        : widget.simulatedTiltDegrees;
    final simTiltRad = effectiveTilt * math.pi / 180.0;

    final firstPoint = UnifiedStylusAdapter.toStrokePoint(
      event: event,
      canvasPos: worldPos,
      pressureEstimator: _pressureEstimator,
      simulatedTiltRadians: simTiltRad,
    );

    _currentStroke = Stroke(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      points: [firstPoint],
      colorHex: widget.selectedColorHex,
      lineWidth: isHighlighter ? math.max(widget.lineWidth * 3.2, 16.0) : widget.lineWidth,
      toolType: isHighlighter ? 'highlighter' : 'pen',
      timestamp: firstPoint.timestamp,
    );

    _activeVertices = StrokeTessellator.tessellateSingle(_currentStroke!);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_touchFilter.shouldAcceptDrawingEvent(event)) return;
    final worldPos = _screenToWorld(event.localPosition);

    if (widget.toolMode == CanvasToolMode.strokeEraser ||
        widget.toolMode == CanvasToolMode.precisionEraser) {
      setState(() => _eraserCursorWorld = worldPos);
      _applyEraser(worldPos);
      return;
    }

    if (_currentStroke == null) return;
    final isPencil = widget.toolMode == CanvasToolMode.pencil;
    final effectiveTilt = isPencil
        ? math.min(widget.simulatedTiltDegrees, 42.0)
        : widget.simulatedTiltDegrees;
    final simTiltRad = effectiveTilt * math.pi / 180.0;

    final pt = UnifiedStylusAdapter.toStrokePoint(
      event: event,
      canvasPos: worldPos,
      pressureEstimator: _pressureEstimator,
      simulatedTiltRadians: simTiltRad,
    );

    final updatedPoints = [..._currentStroke!.points, pt];
    _currentStroke = Stroke(
      id: _currentStroke!.id,
      points: updatedPoints,
      colorHex: _currentStroke!.colorHex,
      lineWidth: _currentStroke!.lineWidth,
      toolType: _currentStroke!.toolType,
      timestamp: _currentStroke!.timestamp,
    );

    _activeVertices = StrokeTessellator.tessellateSingle(_currentStroke!);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    _touchFilter.registerPointerUpOrCancel(event);

    if (_eraserCursorWorld != null) {
      setState(() => _eraserCursorWorld = null);
    }

    if (_currentStroke != null) {
      _undoStack.add(List<Stroke>.from(widget.page.strokes));
      _redoStack.clear();
      widget.page.strokes.add(_currentStroke!);
      _currentStroke = null;
      _activeVertices = null;
      _rebuildCommittedMeshes();
      widget.onHistoryChanged();
      setState(() {});
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touchFilter.registerPointerUpOrCancel(event);
    _currentStroke = null;
    _activeVertices = null;
    _eraserCursorWorld = null;
    setState(() {});
  }

  void _applyEraser(Offset worldPos) {
    final previous = List<Stroke>.from(widget.page.strokes);
    final radius = 18.0 / _zoom;
    final hitBox = Rect.fromCircle(center: worldPos, radius: radius);

    if (widget.toolMode == CanvasToolMode.strokeEraser) {
      widget.page.strokes.removeWhere((s) =>
          s.bounds.overlaps(hitBox) &&
          s.points.any((p) => (p.offset - worldPos).distance <= radius));
    } else {
      final updated = <Stroke>[];
      for (final stroke in widget.page.strokes) {
        if (!stroke.bounds.overlaps(hitBox)) {
          updated.add(stroke);
          continue;
        }
        final segments = <List<StrokePoint>>[];
        var currentSeg = <StrokePoint>[];
        for (final pt in stroke.points) {
          if ((pt.offset - worldPos).distance <= radius) {
            if (currentSeg.isNotEmpty) {
              segments.add(currentSeg);
              currentSeg = [];
            }
          } else {
            currentSeg.add(pt);
          }
        }
        if (currentSeg.isNotEmpty) segments.add(currentSeg);
        for (int i = 0; i < segments.length; i++) {
          if (segments[i].length > 1) {
            updated.add(Stroke(
              id: (i == 0 && segments.length == 1)
                  ? stroke.id
                  : '\_\',
              points: segments[i],
              colorHex: stroke.colorHex,
              lineWidth: stroke.lineWidth,
              toolType: stroke.toolType,
              timestamp: stroke.timestamp,
            ));
          }
        }
      }
      widget.page.strokes = updated;
    }

    if (widget.page.strokes.length != previous.length ||
        !_sameStrokeIds(previous, widget.page.strokes)) {
      _undoStack.add(previous);
      _redoStack.clear();
      _rebuildCommittedMeshes();
      widget.onHistoryChanged();
      setState(() {});
    }
  }

  bool _sameStrokeIds(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].points.length != b[i].points.length) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          final scaleFactor = signal.scrollDelta.dy > 0 ? 0.92 : 1.08;
          final newZoom = (_zoom * scaleFactor).clamp(0.25, 5.0);
          final focal = signal.localPosition;
          setState(() {
            _cameraOffset = focal - ((focal - _cameraOffset) / _zoom) * newZoom;
            _zoom = newZoom;
          });
          widget.onZoomChanged?.call(newZoom);
        }
      },
      child: GestureDetector(
        onScaleStart: (details) {
          if (widget.inputMode == DrawingInputMode.universalStylus &&
              details.pointerCount < 2) {
            return;
          }
          _focalStart = details.localFocalPoint;
          _offsetStart = _cameraOffset;
          _zoomStart = _zoom;
        },
        onScaleUpdate: (details) {
          if (widget.inputMode == DrawingInputMode.universalStylus &&
              details.pointerCount < 2) {
            return;
          }
          final newZoom = (_zoomStart * details.scale).clamp(0.25, 5.0);
          final focalDelta = details.localFocalPoint - _focalStart;
          setState(() {
            _zoom = newZoom;
            _cameraOffset = _offsetStart + focalDelta;
          });
          widget.onZoomChanged?.call(newZoom);
        },
        child: CustomPaint(
          painter: _VectorNotePainter(
            paperConfig: widget.page.paperConfig,
            cameraOffset: _cameraOffset,
            zoom: _zoom,
            devicePixelRatio: dpr,
            grainShader: _grainProgram != null ? _grainShader : null,
            crispVertices: _crispCommittedVertices,
            tiltedVertices: _tiltedCommittedVertices,
            activeVertices: _activeVertices,
            activeIsTilted: _currentStroke?.hasTiltShading ?? false,
            eraserCursorWorld: _eraserCursorWorld,
            eraserRadius: 18.0 / _zoom,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _VectorNotePainter extends CustomPainter {
  final PaperConfig paperConfig;
  final Offset cameraOffset;
  final double zoom;
  final double devicePixelRatio;
  final ui.FragmentShader? grainShader;
  final ui.Vertices? crispVertices;
  final ui.Vertices? tiltedVertices;
  final ui.Vertices? activeVertices;
  final bool activeIsTilted;
  final Offset? eraserCursorWorld;
  final double eraserRadius;

  _VectorNotePainter({
    required this.paperConfig,
    required this.cameraOffset,
    required this.zoom,
    required this.devicePixelRatio,
    required this.grainShader,
    required this.crispVertices,
    required this.tiltedVertices,
    required this.activeVertices,
    required this.activeIsTilted,
    required this.eraserCursorWorld,
    required this.eraserRadius,
  });

  Color _parseBg(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    final rgb = int.tryParse(clean, radix: 16) ?? 0xFFFDFB;
    return Color(0xFF000000 | rgb);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = _parseBg(paperConfig.backgroundColorHex);
    canvas.drawRect(Offset.zero & size, bgPaint);

    canvas.save();
    canvas.translate(cameraOffset.dx, cameraOffset.dy);
    canvas.scale(zoom);

    final visibleWorld = Rect.fromLTWH(
      -cameraOffset.dx / zoom,
      -cameraOffset.dy / zoom,
      size.width / zoom,
      size.height / zoom,
    );

    _drawPaperPattern(canvas, visibleWorld);

    final solidPaint = Paint()..isAntiAlias = true;
    Paint? grainPaint;
    if (grainShader != null) {
      grainShader!
        ..setFloat(0, cameraOffset.dx)
        ..setFloat(1, cameraOffset.dy)
        ..setFloat(2, zoom)
        ..setFloat(3, devicePixelRatio)
        ..setFloat(4, 0.85);
      grainPaint = Paint()
        ..isAntiAlias = true
        ..shader = grainShader;
    }

    if (crispVertices != null) {
      canvas.drawVertices(crispVertices!, BlendMode.srcOver, solidPaint);
    }

    if (tiltedVertices != null) {
      if (grainPaint != null) {
        canvas.drawVertices(tiltedVertices!, BlendMode.modulate, grainPaint);
      } else {
        canvas.drawVertices(tiltedVertices!, BlendMode.srcOver, solidPaint);
      }
    }

    if (activeVertices != null) {
      if (activeIsTilted && grainPaint != null) {
        canvas.drawVertices(activeVertices!, BlendMode.modulate, grainPaint);
      } else {
        canvas.drawVertices(activeVertices!, BlendMode.srcOver, solidPaint);
      }
    }

    if (eraserCursorWorld != null) {
      final fill = Paint()..color = Colors.grey.withValues(alpha: 0.22);
      final ring = Paint()
        ..color = const Color(0xFF3B82F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom;
      canvas.drawCircle(eraserCursorWorld!, eraserRadius, fill);
      canvas.drawCircle(eraserCursorWorld!, eraserRadius, ring);
    }

    canvas.restore();
  }

  void _drawPaperPattern(Canvas canvas, Rect visibleWorld) {
    if (paperConfig.style == PaperStyle.blank) return;

    final linePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.85 / zoom;

    final spacing = paperConfig.spacing;
    final startX = (visibleWorld.left / spacing).floor() * spacing;
    final startY = (visibleWorld.top / spacing).floor() * spacing;

    if (paperConfig.style == PaperStyle.dotted) {
      final dotPaint = Paint()..color = const Color(0xFFCBD5E1);
      final r = 1.25 / zoom;
      for (double x = startX; x <= visibleWorld.right; x += spacing) {
        for (double y = startY; y <= visibleWorld.bottom; y += spacing) {
          canvas.drawCircle(Offset(x, y), r, dotPaint);
        }
      }
      return;
    }

    for (double y = startY; y <= visibleWorld.bottom; y += spacing) {
      canvas.drawLine(
        Offset(visibleWorld.left, y),
        Offset(visibleWorld.right, y),
        linePaint,
      );
    }

    if (paperConfig.style == PaperStyle.grid) {
      for (double x = startX; x <= visibleWorld.right; x += spacing) {
        canvas.drawLine(
          Offset(x, visibleWorld.top),
          Offset(x, visibleWorld.bottom),
          linePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VectorNotePainter oldDelegate) => true;
}

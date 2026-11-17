import 'dart:math' as math;
import 'dart:ui';

enum PaperStyle {
  blank('Blank'),
  lined('Lined'),
  grid('Grid'),
  dotted('Dotted');

  final String label;
  const PaperStyle(this.label);
}

class PaperConfig {
  final PaperStyle style;
  final double spacing;
  final String lineColorHex;
  final String backgroundColorHex;

  const PaperConfig({
    this.style = PaperStyle.grid,
    this.spacing = 32.0,
    this.lineColorHex = '#D1D5DB',
    this.backgroundColorHex = '#FFFFFF',
  });

  PaperConfig copyWith({
    PaperStyle? style,
    double? spacing,
    String? lineColorHex,
    String? backgroundColorHex,
  }) {
    return PaperConfig(
      style: style ?? this.style,
      spacing: spacing ?? this.spacing,
      lineColorHex: lineColorHex ?? this.lineColorHex,
      backgroundColorHex: backgroundColorHex ?? this.backgroundColorHex,
    );
  }

  Map<String, dynamic> toJson() => {
        'style': style.name,
        'spacing': spacing,
        'lineColorHex': lineColorHex,
        'backgroundColorHex': backgroundColorHex,
      };

  factory PaperConfig.fromJson(Map<String, dynamic> json) => PaperConfig(
        style: PaperStyle.values.firstWhere(
          (e) => e.name == json['style'],
          orElse: () => PaperStyle.grid,
        ),
        spacing: (json['spacing'] as num?)?.toDouble() ?? 32.0,
        lineColorHex: json['lineColorHex'] as String? ?? '#D1D5DB',
        backgroundColorHex: json['backgroundColorHex'] as String? ?? '#FFFFFF',
      );
}

class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final double altitude;
  final double azimuth;
  final double timestamp;

  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    this.altitude = math.pi / 2,
    this.azimuth = 0.0,
    required this.timestamp,
  });

  Offset get offset => Offset(x, y);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'pressure': pressure,
        'altitude': altitude,
        'azimuth': azimuth,
        'timestamp': timestamp,
      };

  factory StrokePoint.fromJson(Map<String, dynamic> json) => StrokePoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
        altitude: (json['altitude'] as num?)?.toDouble() ?? (math.pi / 2),
        azimuth: (json['azimuth'] as num?)?.toDouble() ?? 0.0,
        timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      );
}

class Stroke {
  final String id;
  final List<StrokePoint> points;
  final String colorHex;
  final double lineWidth;
  final String toolType;
  final double timestamp;
  late final Rect bounds;
  late final bool hasTiltShading;

  Stroke({
    required this.id,
    required this.points,
    required this.colorHex,
    required this.lineWidth,
    required this.toolType,
    required this.timestamp,
  }) {
    bounds = _computeBounds();
    hasTiltShading =
        toolType != 'highlighter' && points.any((p) => p.altitude < 1.22);
  }

  Rect _computeBounds() {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.x;
    double minY = points.first.y;
    double maxX = points.first.x;
    double maxY = points.first.y;
    bool tilted = false;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
      if (p.altitude < 1.22) tilted = true;
    }

    final maxExpansion = tilted ? 4.5 : 1.7;
    final padding = (lineWidth * 0.5 * maxExpansion) + 2.0;
    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  Stroke cloneWithNewId(String newId) => Stroke(
        id: newId,
        points: List<StrokePoint>.from(points),
        colorHex: colorHex,
        lineWidth: lineWidth,
        toolType: toolType,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points.map((p) => p.toJson()).toList(),
        'colorHex': colorHex,
        'lineWidth': lineWidth,
        'toolType': toolType,
        'timestamp': timestamp,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
        id: json['id'] as String,
        points: (json['points'] as List<dynamic>)
            .map((e) => StrokePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        colorHex: json['colorHex'] as String? ?? '#000000',
        lineWidth: (json['lineWidth'] as num?)?.toDouble() ?? 3.0,
        toolType: json['toolType'] as String? ?? 'pen',
        timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      );
}

class NotePage {
  final String id;
  int pageIndex;
  PaperConfig paperConfig;
  List<Stroke> strokes;
  String searchableText;

  NotePage({
    required this.id,
    required this.pageIndex,
    required this.paperConfig,
    required this.strokes,
    this.searchableText = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'paperConfig': paperConfig.toJson(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'searchableText': searchableText,
      };

  factory NotePage.fromJson(Map<String, dynamic> json) => NotePage(
        id: json['id'] as String,
        pageIndex: json['pageIndex'] as int? ?? 0,
        paperConfig: PaperConfig.fromJson(
          json['paperConfig'] as Map<String, dynamic>? ?? {},
        ),
        strokes: (json['strokes'] as List<dynamic>? ?? [])
            .map((e) => Stroke.fromJson(e as Map<String, dynamic>))
            .toList(),
        searchableText: json['searchableText'] as String? ?? '',
      );
}

class Notebook {
  final String id;
  String title;
  final DateTime creationDate;
  DateTime modificationDate;
  List<NotePage> pages;

  Notebook({
    required this.id,
    required this.title,
    required this.creationDate,
    required this.modificationDate,
    required this.pages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'creationDate': creationDate.toIso8601String(),
        'modificationDate': modificationDate.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Untitled Note',
        creationDate: DateTime.tryParse(json['creationDate'] as String? ?? '') ??
            DateTime.now(),
        modificationDate:
            DateTime.tryParse(json['modificationDate'] as String? ?? '') ??
                DateTime.now(),
        pages: (json['pages'] as List<dynamic>? ?? [])
            .map((e) => NotePage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

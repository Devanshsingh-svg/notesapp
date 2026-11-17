import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/stroke_tessellator.dart';
import '../models/notebook_models.dart';
import 'notebook_search_service.dart';

class HandwritingOcrService {
  HandwritingOcrService._();
  static final HandwritingOcrService instance = HandwritingOcrService._();

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  Future<Uint8List?> renderPageThumbnail(
    NotePage page, {
    int width = 240,
    int height = 320,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(width.toDouble(), height.toDouble());

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    if (page.strokes.isNotEmpty) {
      Rect totalBounds = page.strokes.first.bounds;
      for (final s in page.strokes.skip(1)) {
        totalBounds = totalBounds.expandToInclude(s.bounds);
      }

      const padding = 24.0;
      final contentW = math.max(totalBounds.width + padding * 2, 300.0);
      final contentH = math.max(totalBounds.height + padding * 2, 400.0);
      final scale = math.min(size.width / contentW, size.height / contentH);

      canvas.save();
      canvas.scale(scale);
      canvas.translate(
        -totalBounds.left + padding,
        -totalBounds.top + padding,
      );

      final vertices = StrokeTessellator.tessellateBatch(page.strokes);
      if (vertices != null) {
        canvas.drawVertices(
          vertices,
          BlendMode.srcOver,
          Paint()..isAntiAlias = true,
        );
      }
      canvas.restore();
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<String> recognizeAndIndexPage(Notebook notebook, NotePage page) async {
    if (page.strokes.isEmpty) {
      page.searchableText = '';
      await NotebookSearchService.instance.indexPage(notebook, page);
      return '';
    }

    final pngBytes = await renderPageThumbnail(page, width: 1080, height: 1440);
    if (pngBytes == null) return page.searchableText;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'ocr_${page.id}.png'));
    await tempFile.writeAsBytes(pngBytes, flush: true);

    try {
      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognized = await _recognizer.processImage(inputImage);
      final extracted = recognized.text.trim();
      page.searchableText = extracted;
      await NotebookSearchService.instance.indexPage(notebook, page);
      return extracted;
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}

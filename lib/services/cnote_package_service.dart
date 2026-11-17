import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/notebook_models.dart';
import 'notebook_search_service.dart';

class CnotePackageService {
  CnotePackageService._();
  static final CnotePackageService instance = CnotePackageService._();

  Future<File> exportAndShare(Notebook notebook) async {
    notebook.modificationDate = DateTime.now();
    final archive = Archive();

    final manifestJson =
        const JsonEncoder.withIndent('  ').convert(notebook.toJson());
    final manifestBytes = utf8.encode(manifestJson);
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final readmeBytes = utf8.encode('CustomNote (.cnote) Vector Package v1.0');
    archive.addFile(
      ArchiveFile('Assets/README.txt', readmeBytes.length, readmeBytes),
    );

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw StateError('Failed to encode .cnote archive');
    }

    final safeTitle = notebook.title
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final fileName = '${safeTitle.isEmpty ? 'Notebook' : safeTitle}.cnote';

    final docsDir = await getApplicationDocumentsDirectory();
    final outFile = File(p.join(docsDir.path, fileName));
    await outFile.writeAsBytes(zipData, flush: true);

    await Share.shareXFiles(
      [XFile(outFile.path)],
      subject: '${notebook.title} (.cnote)',
    );

    return outFile;
  }

  Future<Notebook?> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null) return null;

    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestEntry = archive.files.firstWhere(
      (f) => f.name == 'manifest.json' || f.name.endsWith('/manifest.json'),
      orElse: () => throw FormatException('Invalid .cnote package: missing manifest.json'),
    );

    final jsonMap = jsonDecode(
      utf8.decode(manifestEntry.content as List<int>),
    ) as Map<String, dynamic>;

    final imported = Notebook.fromJson(jsonMap);
    await NotebookSearchService.instance.indexNotebook(imported);
    return imported;
  }
}

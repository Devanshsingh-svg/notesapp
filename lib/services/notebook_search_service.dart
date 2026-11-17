import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/notebook_models.dart';

class SearchHit {
  final String notebookId;
  final String notebookTitle;
  final String pageId;
  final int pageIndex;
  final String snippet;

  const SearchHit({
    required this.notebookId,
    required this.notebookTitle,
    required this.pageId,
    required this.pageIndex,
    required this.snippet,
  });
}

class NotebookSearchService {
  NotebookSearchService._();
  static final NotebookSearchService instance = NotebookSearchService._();

  Database? _db;
  bool _ftsAvailable = true;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'custom_note_search.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        try {
          await db.execute('''
            CREATE VIRTUAL TABLE page_search_fts USING fts5(
              notebook_id UNINDEXED,
              page_id UNINDEXED,
              page_index UNINDEXED,
              notebook_title,
              content,
              tokenize='porter unicode61'
            );
          ''');
        } catch (_) {
          _ftsAvailable = false;
          await db.execute('''
            CREATE TABLE page_search_fallback (
              notebook_id TEXT,
              page_id TEXT PRIMARY KEY,
              page_index INTEGER,
              notebook_title TEXT,
              content TEXT
            );
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> indexPage(Notebook notebook, NotePage page) async {
    final db = await database;
    final body = page.searchableText.trim();

    if (_ftsAvailable) {
      await db.delete(
        'page_search_fts',
        where: 'page_id = ?',
        whereArgs: [page.id],
      );
      if (body.isNotEmpty || notebook.title.isNotEmpty) {
        await db.insert('page_search_fts', {
          'notebook_id': notebook.id,
          'page_id': page.id,
          'page_index': page.pageIndex,
          'notebook_title': notebook.title,
          'content': body,
        });
      }
    } else {
      await db.insert(
        'page_search_fallback',
        {
          'notebook_id': notebook.id,
          'page_id': page.id,
          'page_index': page.pageIndex,
          'notebook_title': notebook.title,
          'content': body,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> indexNotebook(Notebook notebook) async {
    for (final page in notebook.pages) {
      await indexPage(notebook, page);
    }
  }

  Future<List<SearchHit>> search(String rawQuery) async {
    final cleaned = rawQuery.replaceAll(RegExp(r'["*:]'), ' ').trim();
    if (cleaned.isEmpty) return [];

    final db = await database;
    if (_ftsAvailable) {
      final tokens = cleaned
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .map((t) => '$t*')
          .join(' ');

      final rows = await db.rawQuery('''
        SELECT
          notebook_id,
          notebook_title,
          page_id,
          page_index,
          snippet(page_search_fts, 4, '[', ']', '...', 12) AS snip
        FROM page_search_fts
        WHERE page_search_fts MATCH ?
        ORDER BY rank
        LIMIT 30
      ''', [tokens]);

      return rows
          .map((r) => SearchHit(
                notebookId: r['notebook_id'] as String? ?? '',
                notebookTitle: r['notebook_title'] as String? ?? 'Notebook',
                pageId: r['page_id'] as String? ?? '',
                pageIndex: (r['page_index'] as num?)?.toInt() ?? 0,
                snippet: (r['snip'] as String? ?? '').trim(),
              ))
          .toList();
    } else {
      final rows = await db.query(
        'page_search_fallback',
        where: 'content LIKE ? OR notebook_title LIKE ?',
        whereArgs: ['%$cleaned%', '%$cleaned%'],
        limit: 30,
      );
      return rows
          .map((r) => SearchHit(
                notebookId: r['notebook_id'] as String? ?? '',
                notebookTitle: r['notebook_title'] as String? ?? 'Notebook',
                pageId: r['page_id'] as String? ?? '',
                pageIndex: (r['page_index'] as num?)?.toInt() ?? 0,
                snippet: r['content'] as String? ?? '',
              ))
          .toList();
    }
  }
}

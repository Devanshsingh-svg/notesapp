import 'package:flutter/material.dart';

import 'engine/input_controller.dart';
import 'models/notebook_models.dart';
import 'services/cnote_package_service.dart';
import 'services/handwriting_ocr_service.dart';
import 'services/notebook_search_service.dart';
import 'widgets/infinite_note_canvas.dart';
import 'widgets/page_navigator_drawer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CustomNoteApp());
}

class CustomNoteApp extends StatelessWidget {
  const CustomNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CustomNote (.cnote)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: const NotebookWorkspaceScreen(),
    );
  }
}

class NotebookWorkspaceScreen extends StatefulWidget {
  const NotebookWorkspaceScreen({super.key});

  @override
  State<NotebookWorkspaceScreen> createState() =>
      _NotebookWorkspaceScreenState();
}

class _NotebookWorkspaceScreenState extends State<NotebookWorkspaceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  final GlobalKey<InfiniteNoteCanvasState> _canvasKey = GlobalKey();

  late Notebook _notebook;
  int _activePageIndex = 0;

  CanvasToolMode _toolMode = CanvasToolMode.pen;
  String _selectedColorHex = '#111827';
  double _lineWidth = 3.5;
  DrawingInputMode _inputMode = DrawingInputMode.universalStylus;
  double _simulatedTiltDegrees = 90.0;
  bool _isRunningOcr = false;

  @override
  void initState() {
    super.initState();
    _notebook = Notebook(
      id: 'nb_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Vector Notebook',
      creationDate: DateTime.now(),
      modificationDate: DateTime.now(),
      pages: [
        NotePage(
          id: 'page_0',
          pageIndex: 0,
          paperConfig: const PaperConfig(style: PaperStyle.grid, spacing: 32.0),
          strokes: [],
        ),
      ],
    );
  }

  NotePage get _activePage => _notebook.pages[_activePageIndex];

  void _addPage() {
    final newIdx = _notebook.pages.length;
    setState(() {
      _notebook.pages.add(
        NotePage(
          id: 'page_${DateTime.now().microsecondsSinceEpoch}',
          pageIndex: newIdx,
          paperConfig: _activePage.paperConfig.copyWith(),
          strokes: [],
        ),
      );
      _activePageIndex = newIdx;
    });
  }

  void _duplicatePage(int index) {
    final source = _notebook.pages[index];
    final clonedStrokes = source.strokes
        .asMap()
        .entries
        .map((e) => e.value.cloneWithNewId(
            '${e.value.id}_copy_${DateTime.now().microsecondsSinceEpoch}_${e.key}'))
        .toList();

    final copy = NotePage(
      id: 'page_${DateTime.now().microsecondsSinceEpoch}',
      pageIndex: index + 1,
      paperConfig: source.paperConfig.copyWith(),
      strokes: clonedStrokes,
      searchableText: source.searchableText,
    );

    setState(() {
      _notebook.pages.insert(index + 1, copy);
      for (int i = 0; i < _notebook.pages.length; i++) {
        _notebook.pages[i].pageIndex = i;
      }
      _activePageIndex = index + 1;
    });
    NotebookSearchService.instance.indexPage(_notebook, copy);
  }

  void _deletePage(int index) {
    if (_notebook.pages.length <= 1) return;
    setState(() {
      _notebook.pages.removeAt(index);
      for (int i = 0; i < _notebook.pages.length; i++) {
        _notebook.pages[i].pageIndex = i;
      }
      if (_activePageIndex >= _notebook.pages.length) {
        _activePageIndex = _notebook.pages.length - 1;
      }
    });
  }

  Future<void> _runHandwritingOcr() async {
    if (_isRunningOcr) return;
    setState(() => _isRunningOcr = true);
    try {
      final text = await HandwritingOcrService.instance
          .recognizeAndIndexPage(_notebook, _activePage);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty
                ? 'No handwriting detected on this page.'
                : 'Indexed OCR text: "$text"',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR note: $e')),
      );
    } finally {
      if (mounted) setState(() => _isRunningOcr = false);
    }
  }

  Future<void> _openFtsSearchDialog() async {
    final controller = TextEditingController();
    List<SearchHit> hits = [];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('SQLite FTS5 Search'),
          content: SizedBox(
            width: 420,
            height: 300,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search handwritten notes (prefix match)...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) async {
                    final res =
                        await NotebookSearchService.instance.search(val);
                    setDialogState(() => hits = res);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: hits.isEmpty
                      ? const Center(
                          child: Text(
                            'Scan handwriting with the OCR button first, then search here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: hits.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final hit = hits[idx];
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text('${hit.pageIndex + 1}'),
                              ),
                              title: Text('Page ${hit.pageIndex + 1}'),
                              subtitle: Text(
                                hit.snippet.isEmpty
                                    ? hit.notebookTitle
                                    : hit.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                final target = _notebook.pages
                                    .indexWhere((p) => p.id == hit.pageId);
                                if (target != -1) {
                                  setState(() => _activePageIndex = target);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCnote() async {
    try {
      await CnotePackageService.instance.exportAndShare(_notebook);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export error: $e')),
      );
    }
  }

  Future<void> _importCnote() async {
    try {
      final imported = await CnotePackageService.instance.pickAndImport();
      if (imported != null && imported.pages.isNotEmpty && mounted) {
        setState(() {
          _notebook = imported;
          _activePageIndex = 0;
        });
        _canvasKey.currentState?.refreshFromModel();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${imported.title}"')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _activePage;
    final canUndo = _canvasKey.currentState?.canUndo ?? false;
    final canRedo = _canvasKey.currentState?.canRedo ?? false;

    return Scaffold(
      key: _scaffoldKey,
      drawer: PageNavigatorDrawer(
        notebook: _notebook,
        activePageIndex: _activePageIndex,
        onSelectPage: (idx) => setState(() => _activePageIndex = idx),
        onAddPage: _addPage,
        onDuplicatePage: _duplicatePage,
        onDeletePage: _deletePage,
      ),
      appBar: AppBar(
        titleSpacing: 8,
        leading: IconButton(
          tooltip: 'Pages (${_activePageIndex + 1}/${_notebook.pages.length})',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: Badge(
            label: Text('${_notebook.pages.length}'),
            child: const Icon(Icons.auto_stories),
          ),
        ),
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Undo',
                onPressed: canUndo ? () => _canvasKey.currentState?.undo() : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: canRedo ? () => _canvasKey.currentState?.redo() : null,
                icon: const Icon(Icons.redo),
              ),
              const SizedBox(width: 6),
              SegmentedButton<CanvasToolMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: CanvasToolMode.pen,
                    icon: Icon(Icons.edit, size: 18),
                    label: Text('Pen'),
                  ),
                  ButtonSegment(
                    value: CanvasToolMode.highlighter,
                    icon: Icon(Icons.highlight, size: 18),
                    label: Text('Highlight'),
                  ),
                  ButtonSegment(
                    value: CanvasToolMode.precisionEraser,
                    icon: Icon(Icons.auto_fix_normal, size: 18),
                    label: Text('Split'),
                  ),
                  ButtonSegment(
                    value: CanvasToolMode.strokeEraser,
                    icon: Icon(Icons.delete_sweep, size: 18),
                    label: Text('Erase'),
                  ),
                ],
                selected: {_toolMode},
                onSelectionChanged: (set) => setState(() => _toolMode = set.first),
              ),
              const SizedBox(width: 10),
              for (final hex in ['#111827', '#2563EB', '#DC2626', '#16A34A'])
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedColorHex = hex;
                    if (_toolMode == CanvasToolMode.precisionEraser ||
                        _toolMode == CanvasToolMode.strokeEraser) {
                      _toolMode = CanvasToolMode.pen;
                    }
                  }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse('FF${hex.replaceAll('#', '')}', radix: 16),
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColorHex == hex
                            ? Colors.amber
                            : Colors.black26,
                        width: _selectedColorHex == hex ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              DropdownButton<PaperStyle>(
                value: page.paperConfig.style,
                underline: const SizedBox.shrink(),
                items: PaperStyle.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                    .toList(),
                onChanged: (style) {
                  if (style != null) {
                    setState(() {
                      page.paperConfig = page.paperConfig.copyWith(style: style);
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              SegmentedButton<DrawingInputMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: DrawingInputMode.activeStylusOnly,
                    label: Text('Stylus'),
                  ),
                  ButtonSegment(
                    value: DrawingInputMode.universalStylus,
                    label: Text('Touch'),
                  ),
                ],
                selected: {_inputMode},
                onSelectionChanged: (set) =>
                    setState(() => _inputMode = set.first),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Scan Handwriting (ML Kit OCR)',
                onPressed: _isRunningOcr ? null : _runHandwritingOcr,
                icon: _isRunningOcr
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
              ),
              IconButton(
                tooltip: 'Search Notes (SQLite FTS5)',
                onPressed: _openFtsSearchDialog,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Export .cnote Archive',
                onPressed: _exportCnote,
                icon: const Icon(Icons.ios_share),
              ),
              IconButton(
                tooltip: 'Import .cnote Archive',
                onPressed: _importCnote,
                icon: const Icon(Icons.folder_open),
              ),
              IconButton(
                tooltip: 'Clear Page',
                onPressed: () => _canvasKey.currentState?.clearPage(),
                icon: const Icon(Icons.layers_clear),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          InfiniteNoteCanvas(
            key: _canvasKey,
            page: page,
            toolMode: _toolMode,
            selectedColorHex: _selectedColorHex,
            lineWidth: _lineWidth,
            inputMode: _inputMode,
            simulatedTiltDegrees: _simulatedTiltDegrees,
            onHistoryChanged: () => setState(() {}),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Colors.black12),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.architecture, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Tilt: ${_simulatedTiltDegrees.round()}°',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                SizedBox(
                  width: 160,
                  child: Slider(
                    value: _simulatedTiltDegrees,
                    min: 15,
                    max: 90,
                    divisions: 75,
                    onChanged: (v) => setState(() => _simulatedTiltDegrees = v),
                  ),
                ),
                Text(
                  _simulatedTiltDegrees < 70 ? 'Graphite Grain' : 'Crisp Ink',
                  style: TextStyle(
                    fontSize: 12,
                    color: _simulatedTiltDegrees < 70
                        ? Colors.orange.shade800
                        : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

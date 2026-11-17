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
      title: 'CollaNote Studio (.cnote)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      home: const CollaNoteWorkspaceScreen(),
    );
  }
}

class CollaNoteWorkspaceScreen extends StatefulWidget {
  const CollaNoteWorkspaceScreen({super.key});

  @override
  State<CollaNoteWorkspaceScreen> createState() =>
      _CollaNoteWorkspaceScreenState();
}

class _CollaNoteWorkspaceScreenState extends State<CollaNoteWorkspaceScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  final GlobalKey<InfiniteNoteCanvasState> _canvasKey = GlobalKey();

  late Notebook _notebook;
  int _activePageIndex = 0;

  CanvasToolMode _toolMode = CanvasToolMode.pen;
  final List<String> _quickColors = ['#111827', '#2563EB', '#DC2626'];
  final List<String> _extraColors = [
    '#16A34A',
    '#D97706',
    '#7C3AED',
    '#DB2777',
    '#0891B2',
    '#FACC15',
  ];
  int _selectedColorSlot = 0;

  final List<double> _strokePresets = [2.2, 4.0, 7.5];
  int _selectedWidthSlot = 1;

  DrawingInputMode _inputMode = DrawingInputMode.universalStylus;
  double _simulatedTiltDegrees = 90.0;
  double _currentZoom = 1.0;
  bool _isRunningOcr = false;

  // Draggable / dockable floating CollaNote tool capsule offset
  Offset _dockOffset = Offset.zero;
  bool _showToolInspector = false;

  @override
  void initState() {
    super.initState();
    _notebook = Notebook(
      id: 'nb_\',
      title: 'Lecture & Study Notes',
      creationDate: DateTime.now(),
      modificationDate: DateTime.now(),
      pages: [
        NotePage(
          id: 'page_0',
          pageIndex: 0,
          paperConfig: const PaperConfig(
            style: PaperStyle.grid,
            spacing: 28.0,
            backgroundColorHex: '#FFFDF9',
          ),
          strokes: [],
        ),
      ],
    );
  }

  NotePage get _activePage => _notebook.pages[_activePageIndex];
  String get _activeColorHex => _quickColors[_selectedColorSlot];
  double get _activeLineWidth => _strokePresets[_selectedWidthSlot];

  void _renameNotebookDialog() {
    final ctrl = TextEditingController(text: _notebook.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Notebook'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Notebook title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final next = ctrl.text.trim();
              if (next.isNotEmpty) {
                setState(() => _notebook.title = next);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _addPage() {
    final newIdx = _notebook.pages.length;
    setState(() {
      _notebook.pages.add(
        NotePage(
          id: 'page_\',
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
            '\_copy_\_\'))
        .toList();

    final copy = NotePage(
      id: 'page_\',
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
          behavior: SnackBarBehavior.floating,
          content: Text(
            text.isEmpty
                ? 'No handwriting detected on Page \.'
                : 'Indexed OCR: "\"',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR error: \')),
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
          title: const Text('Search Handwritten Notes'),
          content: SizedBox(
            width: 400,
            height: 290,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type keyword (SQLite FTS5)...',
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
                            'Tap the OCR scan icon on a page first, then search here.',
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
                                child: Text('\'),
                              ),
                              title: Text('Page \'),
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

  void _openPaperSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Page Template & Paper Tint',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              SegmentedButton<PaperStyle>(
                segments: PaperStyle.values
                    .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                    .toList(),
                selected: {_activePage.paperConfig.style},
                onSelectionChanged: (set) {
                  setState(() {
                    _activePage.paperConfig =
                        _activePage.paperConfig.copyWith(style: set.first);
                  });
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Paper Tint:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  for (final tint in [
                    ('#FFFDF9', 'Warm Cream'),
                    ('#FFFFFF', 'Pure White'),
                    ('#FEF9C3', 'Cornell Yellow'),
                    ('#F1F5F9', 'Cool Gray'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _activePage.paperConfig = _activePage.paperConfig
                                .copyWith(backgroundColorHex: tint.\);
                          });
                          setSheetState(() {});
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _colorFromHex(tint.\),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _activePage.paperConfig.backgroundColorHex ==
                                      tint.\
                                  ? const Color(0xFF2563EB)
                                  : Colors.black26,
                              width: 2.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Input Mode:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  SegmentedButton<DrawingInputMode>(
                    segments: const [
                      ButtonSegment(
                        value: DrawingInputMode.activeStylusOnly,
                        label: Text('Stylus Only'),
                      ),
                      ButtonSegment(
                        value: DrawingInputMode.universalStylus,
                        label: Text('Stylus + Touch'),
                      ),
                    ],
                    selected: {_inputMode},
                    onSelectionChanged: (set) {
                      setState(() => _inputMode = set.first);
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
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
        SnackBar(content: Text('Export error: \')),
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
          SnackBar(content: Text('Imported "\"')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import error: \')),
      );
    }
  }

  Color _colorFromHex(String hex) {
    final clean = hex.replaceAll('#', '').trim();
    return Color(int.parse('FF\', radix: 16));
  }

  Widget _glassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _activePage;
    final canUndo = _canvasKey.currentState?.canUndo ?? false;
    final canRedo = _canvasKey.currentState?.canRedo ?? false;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF1F5F9),
      drawer: PageNavigatorDrawer(
        notebook: _notebook,
        activePageIndex: _activePageIndex,
        onSelectPage: (idx) => setState(() => _activePageIndex = idx),
        onAddPage: _addPage,
        onDuplicatePage: _duplicatePage,
        onDeletePage: _deletePage,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Full-bleed infinite vector canvas
            Positioned.fill(
              child: InfiniteNoteCanvas(
                key: _canvasKey,
                page: page,
                toolMode: _toolMode,
                selectedColorHex: _activeColorHex,
                lineWidth: _activeLineWidth,
                inputMode: _inputMode,
                simulatedTiltDegrees: _simulatedTiltDegrees,
                onHistoryChanged: () => setState(() {}),
                onZoomChanged: (z) => setState(() => _currentZoom = z),
              ),
            ),

            // 1. TOP-LEFT COLLANOTE NAVIGATION PILL (Pages + Title + Undo/Redo)
            Positioned(
              top: 10,
              left: 12,
              child: _glassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Page Thumbnails',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(Icons.grid_view_rounded, size: 20),
                    ),
                    InkWell(
                      onTap: _renameNotebookDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 135),
                              child: Text(
                                _notebook.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down, size: 16),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      height: 18,
                      width: 1,
                      color: const Color(0xFFE2E8F0),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Undo',
                      onPressed:
                          canUndo ? () => _canvasKey.currentState?.undo() : null,
                      icon: const Icon(Icons.undo_rounded, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Redo',
                      onPressed:
                          canRedo ? () => _canvasKey.currentState?.redo() : null,
                      icon: const Icon(Icons.redo_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),

            // 2. TOP-RIGHT UTILITY PILL (OCR, FTS5 Search, Paper Settings, .cnote Menu)
            Positioned(
              top: 10,
              right: 12,
              child: _glassPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Handwriting OCR Scan',
                      onPressed: _isRunningOcr ? null : _runHandwritingOcr,
                      icon: _isRunningOcr
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner_outlined, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Search Notes (FTS5)',
                      onPressed: _openFtsSearchDialog,
                      icon: const Icon(Icons.search_rounded, size: 20),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Paper Template & Stylus Mode',
                      onPressed: _openPaperSettingsSheet,
                      icon: const Icon(Icons.description_outlined, size: 20),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Notebook Options',
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      onSelected: (val) {
                        if (val == 'export') _exportCnote();
                        if (val == 'import') _importCnote();
                        if (val == 'add_page') _addPage();
                        if (val == 'clear') _canvasKey.currentState?.clearPage();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'add_page',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.note_add_outlined),
                            title: Text('New Page'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.ios_share),
                            title: Text('Export .cnote Bundle'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'import',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.folder_open),
                            title: Text('Import .cnote Bundle'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline, color: Colors.red),
                            title: Text('Clear Current Page',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // 3. FLOATING COLLANOTE TOOL CAPSULE (Draggable + 3 Color Slots + 3 Size Dots)
            Positioned(
              top: 66 + _dockOffset.dy,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.translate(
                  offset: Offset(_dockOffset.dx, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _dockOffset += details.delta;
                          });
                        },
                        child: _glassPill(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Drag handle
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 18,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),

                                // Tools: Pen, Graphite Pencil, Highlighter, Split Eraser, Stroke Eraser
                                _toolButton(
                                  mode: CanvasToolMode.pen,
                                  icon: Icons.edit_rounded,
                                  tooltip: 'Fountain / Ballpoint Pen',
                                ),
                                _toolButton(
                                  mode: CanvasToolMode.pencil,
                                  icon: Icons.brush_rounded,
                                  tooltip: 'Graphite Shading Pencil',
                                ),
                                _toolButton(
                                  mode: CanvasToolMode.highlighter,
                                  icon: Icons.border_color_rounded,
                                  tooltip: 'Highlighter',
                                ),
                                _toolButton(
                                  mode: CanvasToolMode.precisionEraser,
                                  icon: Icons.auto_fix_normal_rounded,
                                  tooltip: 'Precision Eraser',
                                ),
                                _toolButton(
                                  mode: CanvasToolMode.strokeEraser,
                                  icon: Icons.delete_sweep_rounded,
                                  tooltip: 'Whole-Stroke Eraser',
                                ),

                                Container(
                                  height: 22,
                                  width: 1,
                                  color: const Color(0xFFE2E8F0),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),

                                // 3 Quick-Tap Color Swatches (CollaNote signature slots)
                                for (int i = 0; i < _quickColors.length; i++)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_selectedColorSlot == i) {
                                          _showToolInspector = !_showToolInspector;
                                        } else {
                                          _selectedColorSlot = i;
                                          if (_toolMode ==
                                                  CanvasToolMode.precisionEraser ||
                                              _toolMode ==
                                                  CanvasToolMode.strokeEraser) {
                                            _toolMode = CanvasToolMode.pen;
                                          }
                                        }
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 140),
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      width: _selectedColorSlot == i ? 26 : 22,
                                      height: _selectedColorSlot == i ? 26 : 22,
                                      decoration: BoxDecoration(
                                        color: _colorFromHex(_quickColors[i]),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _selectedColorSlot == i
                                              ? const Color(0xFF2563EB)
                                              : Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                Container(
                                  height: 22,
                                  width: 1,
                                  color: const Color(0xFFE2E8F0),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),

                                // 3 Stroke Width Preset Dots
                                for (int w = 0; w < _strokePresets.length; w++)
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => _selectedWidthSlot = w),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: _selectedWidthSlot == w
                                            ? const Color(0xFFDBEAFE)
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 5.0 + (w * 4.0),
                                          height: 5.0 + (w * 4.0),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF0F172A),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Expandable Palette & Tilt Popover Toggle
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Palette & Tilt Shading',
                                  onPressed: () => setState(() =>
                                      _showToolInspector = !_showToolInspector),
                                  icon: Icon(
                                    _showToolInspector
                                        ? Icons.expand_less_rounded
                                        : Icons.tune_rounded,
                                    size: 19,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Expandable CollaNote Tool Popover (Extra Colors + Tilt Shading Slider)
                      if (_showToolInspector)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _glassPill(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final hex in _extraColors)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _quickColors[_selectedColorSlot] = hex;
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 5),
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: _colorFromHex(hex),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.black12),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.architecture_rounded,
                                        size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Tilt: \°',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 140,
                                      height: 28,
                                      child: Slider(
                                        value: _simulatedTiltDegrees,
                                        min: 15,
                                        max: 90,
                                        onChanged: (v) => setState(
                                            () => _simulatedTiltDegrees = v),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. BOTTOM-LEFT PAGE PILL & QUICK NEXT-PAGE BUTTON
            Positioned(
              bottom: 14,
              left: 14,
              child: _glassPill(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Page \ / \',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _addPage,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.add_circle_outline_rounded,
                            size: 18, color: Color(0xFF2563EB)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. BOTTOM-RIGHT ZOOM PILL (Tap to reset 100%)
            Positioned(
              bottom: 14,
              right: 14,
              child: GestureDetector(
                onTap: () => _canvasKey.currentState?.resetZoom(),
                child: _glassPill(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '\%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton({
    required CanvasToolMode mode,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _toolMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _toolMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            size: 19,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}

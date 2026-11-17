import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/notebook_models.dart';
import '../services/handwriting_ocr_service.dart';

class PageNavigatorDrawer extends StatefulWidget {
  final Notebook notebook;
  final int activePageIndex;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onAddPage;
  final ValueChanged<int> onDuplicatePage;
  final ValueChanged<int> onDeletePage;

  const PageNavigatorDrawer({
    super.key,
    required this.notebook,
    required this.activePageIndex,
    required this.onSelectPage,
    required this.onAddPage,
    required this.onDuplicatePage,
    required this.onDeletePage,
  });

  @override
  State<PageNavigatorDrawer> createState() => _PageNavigatorDrawerState();
}

class _PageNavigatorDrawerState extends State<PageNavigatorDrawer> {
  final Map<String, Uint8List?> _thumbnails = {};

  @override
  void initState() {
    super.initState();
    _generateThumbnails();
  }

  Future<void> _generateThumbnails() async {
    for (final page in widget.notebook.pages) {
      final png = await HandwritingOcrService.instance.renderPageThumbnail(page);
      if (mounted) {
        setState(() => _thumbnails[page.id] = png);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.notebook.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onAddPage();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Page'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: widget.notebook.pages.length,
                itemBuilder: (context, index) {
                  final page = widget.notebook.pages[index];
                  final isSelected = index == widget.activePageIndex;
                  final thumb = _thumbnails[page.id];

                  return Card(
                    elevation: isSelected ? 3 : 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSelectPage(index);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 64,
                              height: 84,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: thumb != null
                                  ? Image.memory(thumb, fit: BoxFit.cover)
                                  : const Center(
                                      child: Icon(Icons.description_outlined),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Page ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${page.strokes.length} strokes • ${page.paperConfig.style.label}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  if (page.searchableText.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      page.searchableText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                Navigator.pop(context);
                                if (action == 'duplicate') {
                                  widget.onDuplicatePage(index);
                                } else if (action == 'delete') {
                                  widget.onDeletePage(index);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicate Page'),
                                ),
                                if (widget.notebook.pages.length > 1)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete Page',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

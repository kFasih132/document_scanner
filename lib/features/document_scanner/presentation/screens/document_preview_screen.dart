import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../domain/models/scanned_document.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../widgets/filter_preset_selector.dart';
import 'camera_scanner_screen.dart';
import 'document_crop_screen.dart';

class DocumentPreviewScreen extends StatefulWidget {
  final ScannedDocument? document;

  const DocumentPreviewScreen({super.key, this.document});

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  late final PageController _pageController;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showSaveDialog(BuildContext context, int totalPages) {
    final String defaultTitle = widget.document?.title ??
        'Scan_${DateTime.now().day}_${DateTime.now().month}_${DateTime.now().year}';
    final titleController = TextEditingController(text: defaultTitle);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(widget.document != null ? 'Update Document' : 'Save Document'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Document Name',
                  border: OutlineInputBorder(borderRadius: AppSpacing.roundedMd),
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Includes $totalPages scanned pages with applied filters.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<ScannerBloc>().add(SaveDocumentEvent(titleController.text));
                // Return to home
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: Text(widget.document != null ? 'Save Changes' : 'Save & Export'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScannerBloc, ScannerState>(
      builder: (context, state) {
        final List<ScannedPage> pages = state.capturedPages.isNotEmpty
            ? state.capturedPages
            : (widget.document?.pages ?? const []);

        if (pages.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Document Preview')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: AppSpacing.md),
                  const Text('No pages available'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Camera'),
                  ),
                ],
              ),
            ),
          );
        }

        final activePage = _currentPageIndex < pages.length
            ? pages[_currentPageIndex]
            : pages.first;

        final isTabletView = ResponsiveLayout.isTablet(context);
        final bool isBusy = state.status == ScannerStatus.processing ||
            state.status == ScannerStatus.pdfExporting;

        return BlocListener<ScannerBloc, ScannerState>(
          listener: (context, state) {
            if (state.status == ScannerStatus.savedSuccess) {
              Navigator.popUntil(context, (route) => route.isFirst);
            } else if (state.status == ScannerStatus.error && state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          },
          child: Scaffold(
            appBar: PreviewAppBar(
              pageIndex: _currentPageIndex + 1,
              totalPages: pages.length,
              isBusy: isBusy,
              onShare: () {
                context.read<ScannerBloc>().add(SharePdfEvent(document: widget.document));
              },
              onSave: () => _showSaveDialog(context, pages.length),
            ),
            body: Column(
              children: [
                if (isBusy) const LinearProgressIndicator(),
                Expanded(
                  child: isTabletView
                      ? TabletPreviewLayout(
                          pages: pages,
                          activePage: activePage,
                          pageController: _pageController,
                          currentPageIndex: _currentPageIndex,
                          onPageChanged: (index) => setState(() => _currentPageIndex = index),
                        )
                      : MobilePreviewLayout(
                          pages: pages,
                          activePage: activePage,
                          pageController: _pageController,
                          currentPageIndex: _currentPageIndex,
                          onPageChanged: (index) => setState(() => _currentPageIndex = index),
                        ),
                ),
              ],
            ),
          bottomNavigationBar: PreviewBottomActionBar(
            onAddPage: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CameraScannerScreen(),
                  ),
                );
              }
            },
            onCrop: () {
              context.read<ScannerBloc>().add(SelectPageForEditingEvent(_currentPageIndex));
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DocumentCropScreen(),
                ),
              );
            },
            onRotate: () => context.read<ScannerBloc>().add(const RotatePageEvent()),
            onDelete: () {
              context.read<ScannerBloc>().add(DeletePageEvent(_currentPageIndex));
              if (pages.length <= 1) {
                Navigator.pop(context);
              } else {
                setState(() {
                  if (_currentPageIndex > 0) _currentPageIndex--;
                });
              }
            },
          ),
        ),
      );
    },
  );
}
}

class PreviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int pageIndex;
  final int totalPages;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final bool isBusy;

  const PreviewAppBar({
    super.key,
    required this.pageIndex,
    required this.totalPages,
    required this.onSave,
    required this.onShare,
    this.isBusy = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        'Page $pageIndex of $totalPages',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          onPressed: isBusy ? null : onShare,
          tooltip: 'Share PDF',
          icon: const Icon(Icons.share_outlined),
        ),
        FilledButton.tonalIcon(
          onPressed: isBusy ? null : onSave,
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: AppSpacing.roundedFull),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(isBusy ? 'Saving...' : 'Save PDF'),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

class MobilePreviewLayout extends StatelessWidget {
  final List<ScannedPage> pages;
  final ScannedPage activePage;
  final PageController pageController;
  final int currentPageIndex;
  final ValueChanged<int> onPageChanged;

  const MobilePreviewLayout({
    super.key,
    required this.pages,
    required this.activePage,
    required this.pageController,
    required this.currentPageIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Page carousel
        Expanded(
          child: PageView.builder(
            controller: pageController,
            itemCount: pages.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              return SinglePageDisplay(page: pages[index]);
            },
          ),
        ),

        // Filter chips bar
        FilterPresetSelector(
          activeFilter: activePage.filter,
          onFilterSelected: (filter) {
            context.read<ScannerBloc>().add(ApplyFilterEvent(filter));
          },
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

class TabletPreviewLayout extends StatelessWidget {
  final List<ScannedPage> pages;
  final ScannedPage activePage;
  final PageController pageController;
  final int currentPageIndex;
  final ValueChanged<int> onPageChanged;

  const TabletPreviewLayout({
    super.key,
    required this.pages,
    required this.activePage,
    required this.pageController,
    required this.currentPageIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Main page display
        Expanded(
          flex: 3,
          child: PageView.builder(
            controller: pageController,
            itemCount: pages.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              return SinglePageDisplay(page: pages[index]);
            },
          ),
        ),

        // Tablet sidebar for filters & thumbnails
        Expanded(
          flex: 1,
          child: Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filters & Enhancement',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...DocumentFilter.values.map(
                  (filter) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: FilterChip(
                      selected: filter == activePage.filter,
                      label: Text(filter.label),
                      avatar: Icon(filter.icon, size: 16),
                      onSelected: (_) {
                        context.read<ScannerBloc>().add(ApplyFilterEvent(filter));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SinglePageDisplay extends StatelessWidget {
  final ScannedPage page;

  const SinglePageDisplay({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final bool isLocal = File(page.imagePath).existsSync();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppSpacing.roundedMd,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: RotatedBox(
            quarterTurns: (page.rotationDegrees ~/ 90),
            child: ColorFiltered(
              colorFilter: _getColorFilter(page.filter),
              child: isLocal
                  ? Image.file(File(page.imagePath), fit: BoxFit.contain)
                  : const SimulatedDocumentContent(),
            ),
          ),
        ),
      ),
    );
  }

  ColorFilter _getColorFilter(DocumentFilter filter) {
    switch (filter) {
      case DocumentFilter.original:
        return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
      case DocumentFilter.grayscale:
        return const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case DocumentFilter.blackAndWhite:
        return const ColorFilter.matrix(<double>[
          1.5, 1.5, 1.5, 0, -160,
          1.5, 1.5, 1.5, 0, -160,
          1.5, 1.5, 1.5, 0, -160,
          0, 0, 0, 1, 0,
        ]);
      case DocumentFilter.magicColor:
        return const ColorFilter.matrix(<double>[
          1.2, 0, 0, 0, -10,
          0, 1.2, 0, 0, -10,
          0, 0, 1.2, 0, -10,
          0, 0, 0, 1, 0,
        ]);
    }
  }
}

class SimulatedDocumentContent extends StatelessWidget {
  const SimulatedDocumentContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 450,
      color: Colors.white,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: 80, height: 16, color: Colors.black87),
              Container(width: 40, height: 16, color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(width: double.infinity, height: 8, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.sm),
          Container(width: double.infinity, height: 8, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.sm),
          Container(width: 200, height: 8, color: Colors.grey.shade300),
          const SizedBox(height: AppSpacing.xl),
          Container(width: double.infinity, height: 120, color: Colors.grey.shade100),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(width: 100, height: 2, color: Colors.black54),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Authorized Signature',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewBottomActionBar extends StatelessWidget {
  final VoidCallback onAddPage;
  final VoidCallback onCrop;
  final VoidCallback onRotate;
  final VoidCallback onDelete;

  const PreviewBottomActionBar({
    super.key,
    required this.onAddPage,
    required this.onCrop,
    required this.onRotate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      elevation: 3,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.add_a_photo_outlined),
          selectedIcon: Icon(Icons.add_a_photo),
          label: 'Add Page',
        ),
        NavigationDestination(
          icon: Icon(Icons.crop_rotate_outlined),
          selectedIcon: Icon(Icons.crop_rotate),
          label: 'Crop',
        ),
        NavigationDestination(
          icon: Icon(Icons.rotate_90_degrees_cw_outlined),
          selectedIcon: Icon(Icons.rotate_90_degrees_cw),
          label: 'Rotate',
        ),
        NavigationDestination(
          icon: Icon(Icons.delete_outline_rounded),
          selectedIcon: Icon(Icons.delete_rounded),
          label: 'Delete',
        ),
      ],
      selectedIndex: 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            onAddPage();
            break;
          case 1:
            onCrop();
            break;
          case 2:
            onRotate();
            break;
          case 3:
            onDelete();
            break;
        }
      },
    );
  }
}

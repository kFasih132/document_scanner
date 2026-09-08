import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/shared/widgets/app_m3_button.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/responsive_layout.dart';
import '../../domain/models/scanned_document.dart';
import '../bloc/scanner_bloc.dart';
import '../bloc/scanner_event.dart';
import '../bloc/scanner_state.dart';
import '../widgets/document_options_sheet.dart';
import 'camera_scanner_screen.dart';
import 'document_preview_screen.dart';
import 'scanner_settings_screen.dart';

class ScannerHomeScreen extends StatefulWidget {
  const ScannerHomeScreen({super.key});

  @override
  State<ScannerHomeScreen> createState() => _ScannerHomeScreenState();
}

class _ScannerHomeScreenState extends State<ScannerHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Load persisted documents from local storage on launch
    context.read<ScannerBloc>().add(const LoadSavedDocumentsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ScannerBloc, ScannerState>(
      listener: (context, state) {
        if (state.status == ScannerStatus.pdfExportSuccess && state.lastExportedPdfPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF saved: ${state.lastExportedPdfPath}'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Share',
                onPressed: () {
                  final doc = state.recentDocuments
                      .where((d) => d.pdfPath == state.lastExportedPdfPath)
                      .firstOrNull;
                  if (doc != null) {
                    context.read<ScannerBloc>().add(SharePdfEvent(document: doc));
                  }
                },
              ),
            ),
          );
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
        appBar: const ScannerHomeAppBar(),
        body: BlocBuilder<ScannerBloc, ScannerState>(
          buildWhen: (previous, current) {
            return previous.recentDocuments != current.recentDocuments ||
                previous.status != current.status;
          },
          builder: (context, state) {
            return ResponsiveLayout(
              mobile: ScannerHomeBody(
                documents: state.recentDocuments,
                crossAxisCount: 1,
              ),
              tablet7Inch: ScannerHomeBody(
                documents: state.recentDocuments,
                crossAxisCount: 2,
              ),
              tablet10Inch: ScannerHomeBody(
                documents: state.recentDocuments,
                crossAxisCount: 3,
              ),
            );
          },
        ),
        floatingActionButton: const ScannerStartFab(),
      ),
    );
  }
}

class ScannerHomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ScannerHomeAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs + 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppSpacing.roundedSm,
            ),
            child: Icon(
              Icons.document_scanner_rounded,
              color: theme.colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text(
            'DocScanner M3',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search documents',
          onPressed: () {
            // TODO: [ ] Implement full-text and title document search
          },
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Scanner & AI Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ScannerSettingsScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class ScannerHomeBody extends StatelessWidget {
  final List<ScannedDocument> documents;
  final int crossAxisCount;

  const ScannerHomeBody({
    super.key,
    required this.documents,
    required this.crossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Quick Action & Statistics Card
        SliverToBoxAdapter(
          child: Padding(
            padding: AppSpacing.paddingScreen,
            child: QuickScanHeroCard(
              totalDocs: documents.length,
            ),
          ),
        ),

        // Section Title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Documents',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${documents.length} files',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Document Cards Grid
        if (documents.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyDocumentsView(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: crossAxisCount == 1 ? 3.0 : 1.25,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return ScannedDocumentCard(document: documents[index]);
                },
                childCount: documents.length,
              ),
            ),
          ),

        // Bottom spacing for FAB clearance
        const SliverToBoxAdapter(
          child: SizedBox(height: 88),
        ),
      ],
    );
  }
}

class QuickScanHeroCard extends StatelessWidget {
  final int totalDocs;

  const QuickScanHeroCard({super.key, required this.totalDocs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'High Quality Capture',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Auto edge detection, OCR & PDF export with M3 precision.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppM3Button(
                    label: 'Start New Scan',
                    icon: Icons.camera_alt_outlined,
                    variant: AppButtonVariant.filled,
                    onPressed: () {
                      context.read<ScannerBloc>().add(const ResetScannerEvent());
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CameraScannerScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 32,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScannedDocumentCard extends StatelessWidget {
  final ScannedDocument document;

  const ScannedDocumentCard({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.roundedLg,
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: AppSpacing.roundedLg,
        onTap: () {
          // Open existing document
          context.read<ScannerBloc>().add(OpenDocumentForEditingEvent(document));
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocumentPreviewScreen(document: document),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Document Thumbnail
              Container(
                width: 56,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: AppSpacing.roundedSm,
                ),
                child: Center(
                  child: Icon(
                    Icons.description_outlined,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Title and Meta Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      document.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} • ${_formatDate(document.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Add Pages to this document button
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined),
                tooltip: 'Add pages to this document',
                onPressed: () {
                  context.read<ScannerBloc>().add(OpenDocumentForEditingEvent(document));
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CameraScannerScreen(),
                    ),
                  );
                },
              ),

              // Options Menu Icon
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                tooltip: 'Document options',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(AppSpacing.radiusXl),
                      ),
                    ),
                    builder: (sheetContext) => DocumentOptionsSheet(document: document),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class EmptyDocumentsView extends StatelessWidget {
  const EmptyDocumentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_none_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'No documents scanned yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap the camera button below to scan your first page.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerStartFab extends StatelessWidget {
  const ScannerStartFab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FloatingActionButton.extended(
      onPressed: () {
        context.read<ScannerBloc>().add(const ResetScannerEvent());
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CameraScannerScreen(),
          ),
        );
      },
      icon: const Icon(Icons.document_scanner_rounded),
      label: const Text(
        'Scan Now',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
    );
  }
}

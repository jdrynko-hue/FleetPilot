import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'media_repository.dart';
import 'pdf_saver.dart';

/// Locally selected bytes: the original name never becomes a Storage path.
class GarageSelectedMedia {
  const GarageSelectedMedia({required this.bytes, required this.mime});
  final Uint8List bytes;
  final String mime;
}

typedef GarageMediaList = Future<List<String>> Function(
  GarageMediaCategory category,
);
typedef GarageMediaRead = Future<Uint8List> Function(
  GarageMediaCategory category,
  String fileName,
);
typedef GarageMediaWrite = Future<String> Function(
  GarageMediaCategory category,
  String mime,
  Uint8List bytes,
);
typedef GarageMediaPick = Future<GarageSelectedMedia?> Function(
  GarageMediaCategory category,
);
typedef GaragePdfSave = Future<void> Function(
  String fileName,
  Uint8List bytes,
);

/// Private Garage job evidence screen. Callers decide which tabs to offer,
/// but all access is ALSO enforced by Supabase Auth & Storage RLS.
///
/// The screen intentionally never builds public URLs or signed URLs.
/// Internal Garage only; not wired into Fleet or the public navigation.
class GarageOrderMediaScreen extends StatefulWidget {
  const GarageOrderMediaScreen({
    required this.loadFiles,
    required this.readFile,
    required this.uploadFile,
    required this.pickFile,
    required this.savePdf,
    this.showDocuments = false,
    this.canUploadPhotos = true,
    this.canUploadDocuments = false,
    super.key,
  });

  factory GarageOrderMediaScreen.forRepository({
    required GarageMediaRepository repository,
    required String workspaceId,
    required String orderId,
    GaragePdfSave? savePdf,
    bool showDocuments = false,
    bool canUploadPhotos = true,
    bool canUploadDocuments = false,
    Key? key,
  }) {
    return GarageOrderMediaScreen(
      key: key,
      loadFiles: (category) => repository.listFileNames(
        workspaceId: workspaceId, orderId: orderId, category: category,
      ),
      readFile: (category, fileName) => repository.download(
        workspaceId: workspaceId, orderId: orderId,
        category: category, fileName: fileName,
      ),
      uploadFile: (category, mime, data) => repository.upload(
        workspaceId: workspaceId, orderId: orderId,
        category: category, mime: mime, data: data,
      ),
      pickFile: pickGarageFile,
      savePdf: savePdf ?? saveGaragePdfToDevice,
      showDocuments: showDocuments,
      canUploadPhotos: canUploadPhotos,
      canUploadDocuments: canUploadDocuments,
    );
  }

  final GarageMediaList loadFiles;
  final GarageMediaRead readFile;
  final GarageMediaWrite uploadFile;
  final GarageMediaPick pickFile;
  final GaragePdfSave savePdf;

  final bool showDocuments;
  final bool canUploadPhotos;
  final bool canUploadDocuments;

  @override
  State<GarageOrderMediaScreen> createState() => _GarageOrderMediaScreenState();
}

/// Uses the existing file_picker dependency. MIME comes from an allowlisted
/// extension; bucket rules independently enforce size and MIME server-side.
Future<GarageSelectedMedia?> pickGarageFile(
  GarageMediaCategory category,
) async {
  final photo = category == GarageMediaCategory.photo;
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: photo
        ? ['jpg', 'jpeg', 'png', 'webp']
        : ['pdf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final ext = file.extension?.toLowerCase() ??
      file.name.split('.').last.toLowerCase();
  final mime = switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    _ => throw const FormatException('Unsupported Garage file'),
  };
  GarageMediaPaths.extensionFor(category, mime);
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty ||
      bytes.length > GarageMediaPaths.maxFileBytes) {
    throw const FormatException('File too large or missing bytes');
  }
  return GarageSelectedMedia(bytes: bytes, mime: mime);
}

class _GarageOrderMediaScreenState extends State<GarageOrderMediaScreen> {
  GarageMediaCategory _category = GarageMediaCategory.photo;
  List<String> _files = const [];
  bool _busy = false;
  bool _loading = true;
  String? _error;
  int _scope = 0;
  int _listVersion = 0;
  int _operationVersion = 0;
  bool _savingPdf = false;
  DialogRoute<void>? _previewRoute;

  bool get _pl => AppLocale.language.value == 'pl';
  String _tr(String pl, String en) => _pl ? pl : en;
  bool get _canUpload => _category == GarageMediaCategory.photo
      ? widget.canUploadPhotos
      : widget.canUploadDocuments;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant GarageOrderMediaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadFiles != widget.loadFiles ||
        oldWidget.readFile != widget.readFile ||
        oldWidget.uploadFile != widget.uploadFile ||
        oldWidget.pickFile != widget.pickFile ||
        oldWidget.savePdf != widget.savePdf ||
        oldWidget.showDocuments != widget.showDocuments ||
        oldWidget.canUploadPhotos != widget.canUploadPhotos ||
        oldWidget.canUploadDocuments != widget.canUploadDocuments) {
      _scope++;
      _operationVersion++;
      _busy = false;
      _savingPdf = false;
      _category = GarageMediaCategory.photo;
      _dismissPreview();
      _refresh();
    }
  }

  @override
  void dispose() {
    _scope++;
    _listVersion++;
    _operationVersion++;
    _dismissPreview();
    super.dispose();
  }

  bool _currentOperation(int scope, int operation) => mounted &&
      scope == _scope && operation == _operationVersion;

  // Remove only our own preview, never a different route above it. Scope
  // replacement may happen during build, so defer the Navigator mutation.
  void _dismissPreview() {
    final route = _previewRoute;
    _previewRoute = null;
    if (route == null) return;
    final navigator = route.navigator;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _showPreview(WidgetBuilder builder) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(context: context, builder: builder);
    _previewRoute = route;
    try {
      await navigator.push<void>(route);
    } finally {
      if (identical(_previewRoute, route)) _previewRoute = null;
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _busy) return;
    final requested = _category;
    final version = ++_listVersion;
    final loadFiles = widget.loadFiles;
    bool current() => mounted && version == _listVersion;
    setState(() {
      _loading = true;
      _files = const []; // Revoke previously cached names immediately.
      _error = null;
    });
    try {
      final names = await loadFiles(requested);
      if (!current()) return;
      setState(() => _files = List.unmodifiable(names));
    } catch (_) {
      if (!current()) return;
      setState(() {
        _error = _tr(
          'Nie udało się pobrać dokumentacji. Spróbuj ponownie.',
          'Could not load job files. Please retry.',
        );
      });
    } finally {
      if (current()) {
        setState(() => _loading = false);
      }
    }
  }

  void _switch(GarageMediaCategory category) {
    if (_category == category || _busy ||
        (category == GarageMediaCategory.document && !widget.showDocuments)) return;
    setState(() => _category = category);
    _refresh();
  }

  Future<void> _upload() async {
    if (_busy || _loading || !_canUpload) return;
    final category = _category;
    final scope = _scope;
    final operation = ++_operationVersion;
    final pickFile = widget.pickFile;
    final uploadFile = widget.uploadFile;
    bool current() => _currentOperation(scope, operation);
    setState(() => _busy = true);
    try {
      final selected = await pickFile(category);
      if (!current() || selected == null) return;
      if (selected.bytes.isEmpty ||
          selected.bytes.length > GarageMediaPaths.maxFileBytes) {
        throw const FormatException('Invalid upload size');
      }
      GarageMediaPaths.extensionFor(category, selected.mime);
      await uploadFile(category, selected.mime, selected.bytes);
      if (!current()) return;
      setState(() {
        _busy = false;
        _files = const [];
      });
      await _refresh();
    } catch (_) {
      if (!current()) return;
      setState(() {
        _error = _tr(
          'Nie udało się dodać pliku. Sprawdź uprawnienia i spróbuj ponownie.',
          'Upload failed. Check permissions and retry.',
        );
      });
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _open(String fileName) async {
    if (_busy || _loading || !_files.contains(fileName)) return;
    final category = _category;
    final scope = _scope;
    final operation = ++_operationVersion;
    final readFile = widget.readFile;
    final savePdf = widget.savePdf;
    bool current() => _currentOperation(scope, operation);
    setState(() => _busy = true);
    try {
      final bytes = await readFile(category, fileName);
      if (!current()) return;
      if (category == GarageMediaCategory.document) {
        // Fetch privately first; Safari requires the final download action to
        // run in a *new* explicit user gesture, not after a network await.
        // Alert that a downloaded copy is no longer subject to Garage RLS.
        await _showPreview((dialogContext) => !current()
          ? const SizedBox.shrink() : AlertDialog(
            title: Text(_tr('Zapisz PDF', 'Save PDF')),
            content: Text(_tr(
              'Plik zostanie zapisany na tym urządzeniu. '
                  'Po pobraniu dostęp do tej kopii nie jest już kontrolowany '
                  'przez uprawnienia warsztatu.',
              'This will save a copy on your device. After downloading, '
                  'the workshop can no longer revoke access to that copy.',
            )),
            actions: [
              TextButton(
                key: const Key('garage_media_cancel_pdf'),
                onPressed: () {
                  if (current()) _dismissPreview();
                },
                child: Text(_tr('Anuluj', 'Cancel')),
              ),
              FilledButton(
                key: const Key('garage_media_save_pdf'),
                onPressed: () => _savePdfAndClose(
                  fileName, bytes, savePdf, scope, operation,
                ),
                child: Text(_tr('Zapisz PDF', 'Save PDF')),
              ),
            ],
          ));
      } else {
        await _showPreview((context) => !current()
          ? const SizedBox.shrink() : Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: Text(_tr('Zdjęcie naprawy', 'Repair photo')),
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      key: const Key('garage_media_close_preview'),
                      tooltip: _tr('Zamknij', 'Close'),
                      onPressed: () {
                        if (current()) _dismissPreview();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(bytes,
                      key: const Key('garage_media_photo_preview'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ));
      }
    } catch (_) {
      if (!current()) return;
      setState(() {
        _files = const [];
        _error = _tr(
          'Nie udało się otworzyć pliku. Sprawdź aktualne uprawnienia.',
          'Cannot open this file. Check your current permissions.',
        );
      });
    } finally {
      if (current()) {
        setState(() { _busy = false; _savingPdf = false; });
        // A dismissed preview's saved callbacks must not export its bytes.
        _operationVersion++;
      }
    }
  }

  Future<void> _savePdfAndClose(
    String fileName,
    Uint8List bytes,
    GaragePdfSave savePdf,
    int scope,
    int operation,
  ) async {
    bool current() => _currentOperation(scope, operation);
    if (!current() || _savingPdf) return;
    _savingPdf = true;
    try {
      // Invoke the save operation directly from the user button callback.
      await savePdf(fileName, bytes);
      if (current()) _dismissPreview();
    } catch (_) {
      if (current()) {
        _dismissPreview();
        setState(() {
          _error = _tr(
            'Zapis PDF nie powiódł się. Spróbuj ponownie.',
            'Could not save the PDF. Please retry.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final version = _listVersion;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Dokumentacja naprawy', 'Repair evidence')),
        actions: [
          IconButton(
            key: const Key('garage_media_refresh'),
            tooltip: _tr('Odśwież', 'Refresh'),
            onPressed: _busy || _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canUpload
          ? FloatingActionButton.extended(
              key: const Key('garage_media_upload'),
              onPressed: _busy || _loading ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: Text(_tr('Dodaj plik', 'Add file')),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.showDocuments)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<GarageMediaCategory>(
                  segments: [
                    ButtonSegment(
                      value: GarageMediaCategory.photo,
                      label: Text(_tr('Zdjęcia', 'Photos')),
                      icon: const Icon(Icons.photo_outlined),
                    ),
                    ButtonSegment(
                      value: GarageMediaCategory.document,
                      label: Text(_tr('PDF', 'PDFs')),
                      icon: const Icon(Icons.description_outlined),
                    ),
                  ],
                  selected: {_category},
                  onSelectionChanged: _busy ? null :
                      (values) => _switch(values.first),
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, key: const Key('garage_media_error')),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _files.isEmpty
                      ? Center(
                          child: Text(
                            _error == null
                              ? _tr('Brak plików', 'No files yet')
                              : _tr('Spróbuj ponownie', 'Please retry'),
                            key: const Key('garage_media_empty'),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final name = _files[index];
                            return ListTile(
                              key: Key('garage_media_item_$index'),
                              leading: Icon(
                                _category == GarageMediaCategory.photo
                                    ? Icons.image_outlined
                                    : Icons.picture_as_pdf_outlined,
                              ),
                              title: Text(
                                _category == GarageMediaCategory.photo
                                  ? _tr('Zdjęcie', 'Photo') + ' ${index + 1}'
                                  : _tr('Dokument PDF', 'PDF document') +
                                      ' ${index + 1}',
                              ),
                              trailing: const Icon(Icons.open_in_new),
                              enabled: !_busy,
                              onTap: () {
                                if (scope == _scope && version == _listVersion) {
                                  _open(name);
                                }
                              },
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

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/localization.dart';
import 'media_repository.dart';

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
    required GaragePdfSave savePdf,
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
      savePdf: savePdf,
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

  Future<void> _refresh() async {
    if (_busy) return;
    final requested = _category;
    setState(() {
      _loading = true;
      _files = const []; // Revoke previously cached names immediately.
      _error = null;
    });
    try {
      final names = await widget.loadFiles(requested);
      if (!mounted || requested != _category) return;
      setState(() => _files = List.unmodifiable(names));
    } catch (_) {
      if (!mounted || requested != _category) return;
      setState(() {
        _error = _tr(
          'Nie udało się pobrać dokumentacji. Spróbuj ponownie.',
          'Could not load job files. Please retry.',
        );
      });
    } finally {
      if (mounted && requested == _category) {
        setState(() => _loading = false);
      }
    }
  }

  void _switch(GarageMediaCategory category) {
    if (_category == category || _busy) return;
    setState(() => _category = category);
    _refresh();
  }

  Future<void> _upload() async {
    if (_busy || _loading || !_canUpload) return;
    final category = _category;
    setState(() => _busy = true);
    try {
      final selected = await widget.pickFile(category);
      if (selected == null) return;
      if (selected.bytes.isEmpty ||
          selected.bytes.length > GarageMediaPaths.maxFileBytes) {
        throw const FormatException('Invalid upload size');
      }
      GarageMediaPaths.extensionFor(category, selected.mime);
      await widget.uploadFile(category, selected.mime, selected.bytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _files = const [];
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _tr(
          'Nie udało się dodać pliku. Sprawdź uprawnienia i spróbuj ponownie.',
          'Upload failed. Check permissions and retry.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String fileName) async {
    if (_busy || _loading) return;
    final category = _category;
    setState(() => _busy = true);
    try {
      final bytes = await widget.readFile(category, fileName);
      if (!mounted || category != _category) return;
      if (category == GarageMediaCategory.document) {
        await widget.savePdf(fileName, bytes);
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
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
                      onPressed: () => Navigator.of(context).pop(),
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
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _files = const [];
        _error = _tr(
          'Nie udało się otworzyć pliku. Sprawdź aktualne uprawnienia.',
          'Cannot open this file. Check your current permissions.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                              onTap: () => _open(name),
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

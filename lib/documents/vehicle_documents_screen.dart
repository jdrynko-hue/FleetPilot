import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/localization.dart';
import '../data/fleet_repository.dart';
import '../data/models.dart';

class VehicleDocumentsScreen extends StatefulWidget {
  const VehicleDocumentsScreen({
    required this.company,
    required this.vehicleId,
    required this.registration,
    required this.canManage,
    super.key,
  });

  final CompanyMembership company;
  final String vehicleId;
  final String registration;
  final bool canManage;

  @override
  State<VehicleDocumentsScreen> createState() => _VehicleDocumentsScreenState();
}

class _VehicleDocumentsScreenState extends State<VehicleDocumentsScreen> {
  static const _bucket = 'fleetpilot-documents';
  static const _maxBytes = 15 * 1024 * 1024;
  static const _categories = [
    'mot',
    'insurance',
    'registration',
    'service',
    'repair_invoice',
    'damage_photo',
    'other',
  ];

  final _client = Supabase.instance.client;
  final _repository = FleetRepository();
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final rows = await _client
        .from('fleet_documents')
        .select()
        .eq('company_id', widget.company.companyId)
        .eq('vehicle_id', widget.vehicleId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  void _message(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message.toString())));
  }

  String _mimeFor(String extension) => switch (extension) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => '',
  };

  Future<void> _add() async {
    if (_busy || !widget.canManage) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'webp',
          'heic',
          'heif',
          'doc',
          'docx',
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final extension = file.name.split('.').last.toLowerCase();
      final mime = _mimeFor(extension);
      final bytes = file.bytes;
      if (mime.isEmpty ||
          file.size == 0 ||
          file.size > _maxBytes ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > _maxBytes) {
        _message(tr('document_invalid'));
        return;
      }

      final repairs = await _repository.fetchRepairs(
        widget.company.companyId,
        vehicleId: widget.vehicleId,
      );
      if (!mounted) return;

      final controller = TextEditingController(text: file.name);
      String category = 'other';
      String? repairId;
      final details =
          await showDialog<({String title, String category, String? repairId})>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, update) => AlertDialog(
                title: Text(tr('add_document')),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        maxLength: 180,
                        decoration: InputDecoration(
                          labelText: tr('document_title'),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr('document_category'),
                        ),
                        items: [
                          for (final value in _categories)
                            DropdownMenuItem(
                              value: value,
                              child: Text(tr('document_$value')),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          update(() {
                            category = value;
                            if (category != 'repair_invoice') repairId = null;
                          });
                        },
                      ),
                      if (category == 'repair_invoice' &&
                          repairs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: repairId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('linked_repair'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(tr('not_assigned')),
                            ),
                            for (final repair in repairs)
                              DropdownMenuItem(
                                value: repair.id,
                                child: Text(
                                  '${repair.description ?? tr('repair')} (${repair.status})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => update(
                            () => repairId = (value == null || value.isEmpty)
                                ? null
                                : value,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('cancel')),
                  ),
                  FilledButton(
                    onPressed: () {
                      final title = controller.text.trim();
                      if (title.isEmpty) return;
                      Navigator.pop(context, (
                        title: title,
                        category: category,
                        repairId: repairId,
                      ));
                    },
                    child: Text(tr('upload_document')),
                  ),
                ],
              ),
            ),
          );
      controller.dispose();
      if (details == null || !mounted) return;

      setState(() => _busy = true);
      final filename = '${DateTime.now().microsecondsSinceEpoch}.$extension';
      final path = '${widget.company.companyId}/${widget.vehicleId}/$filename';
      var uploaded = false;
      try {
        await _client.storage
            .from(_bucket)
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mime, upsert: false),
            );
        uploaded = true;
        await _client.from('fleet_documents').insert({
          'company_id': widget.company.companyId,
          'vehicle_id': widget.vehicleId,
          'title': details.title,
          'category': details.category,
          'repair_id': details.repairId,
          'original_filename': file.name,
          'mime_type': mime,
          'size_bytes': bytes.length,
          'storage_path': path,
        });
        await _refresh();
        _message(tr('document_uploaded'));
      } catch (error) {
        if (uploaded) {
          try {
            await _client.storage.from(_bucket).remove([path]);
          } catch (_) {}
        }
        _message(error);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } catch (error) {
      _message(error);
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    try {
      final url = await _client.storage
          .from(_bucket)
          .createSignedUrl(row['storage_path'].toString(), 120);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault)) {
        throw StateError(tr('document_open_failed'));
      }
    } catch (error) {
      _message(error);
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('delete_document')),
        content: Text(row['title'].toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('delete_document')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _client
          .from('fleet_documents')
          .delete()
          .eq('company_id', widget.company.companyId)
          .eq('id', row['id'].toString());
      await _client.storage.from(_bucket).remove([
        row['storage_path'].toString(),
      ]);
      await _refresh();
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('documents')} • ${widget.registration}'),
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(tr('add_document')),
            )
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(_load),
                child: Text('${tr('try_again')}: ${snapshot.error}'),
              ),
            );
          }
          final documents = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: documents.isEmpty
                  ? [
                      const SizedBox(height: 90),
                      const Icon(Icons.folder_open_outlined, size: 64),
                      const SizedBox(height: 12),
                      Center(child: Text(tr('no_documents'))),
                    ]
                  : [
                      for (final document in documents)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              document['category'] == 'damage_photo'
                                  ? Icons.photo_camera_outlined
                                  : Icons.description_outlined,
                            ),
                            title: Text(document['title'].toString()),
                            subtitle: Text(
                              '${tr('document_${document['category']}')} • '
                              '${document['original_filename']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _open(document),
                            trailing: widget.canManage
                                ? IconButton(
                                    tooltip: tr('delete_document'),
                                    onPressed: _busy
                                        ? null
                                        : () => _remove(document),
                                    icon: const Icon(Icons.delete_outline),
                                  )
                                : const Icon(Icons.open_in_new),
                          ),
                        ),
                    ],
            ),
          );
        },
      ),
    );
  }
}

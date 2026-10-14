import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Private Garage Storage paths; permissions are enforced server-side by RLS.
/// Never use public or signed URLs for these workshop photos and PDFs.
enum GarageMediaCategory { photo, document }

class GarageMediaPaths {
  const GarageMediaPaths._();

  static const bucket = 'flotaryx-garage-private';
  static const maxFileBytes = 5 * 1024 * 1024;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
    r'[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _filename = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
    r'[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|pdf)$',
  );

  static String folderName(GarageMediaCategory kind) =>
      kind == GarageMediaCategory.photo ? 'photos' : 'documents';

  static void requireIds(String workspaceId, String orderId) {
    if (!_uuid.hasMatch(workspaceId) || !_uuid.hasMatch(orderId)) {
      throw ArgumentError('Garage media requires lowercase UUIDs');
    }
  }

  static String folder({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
  }) {
    requireIds(workspaceId, orderId);
    return '$workspaceId/$orderId/${folderName(category)}';
  }

  static String extensionFor(GarageMediaCategory category, String mime) {
    if (category == GarageMediaCategory.document &&
        mime == 'application/pdf') {
      return 'pdf';
    }
    if (category == GarageMediaCategory.photo) {
      switch (mime) {
        case 'image/jpeg': return 'jpg';
        case 'image/png': return 'png';
        case 'image/webp': return 'webp';
      }
    }
    throw FormatException('Unsupported Garage media type: $mime');
  }

  /// Generates a random UUIDv4 path, never from customer identifying data.
  static String createUploadPath({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
    required String mime,
    required int fileSize,
  }) {
    if (fileSize < 1 || fileSize > maxFileBytes) {
      throw RangeError.range(fileSize, 1, maxFileBytes, 'fileSize');
    }
    final root = folder(workspaceId: workspaceId, orderId: orderId,
        category: category);
    final extension = extensionFor(category, mime);
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
    return '$root/$id.$extension';
  }

  /// Validates a single object name, preventing directory traversal.
  static String validatedPath({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
    required String fileName,
  }) {
    final root = folder(workspaceId: workspaceId, orderId: orderId,
        category: category);
    if (!_filename.hasMatch(fileName)) {
      throw ArgumentError.value(fileName, 'fileName', 'Invalid object name');
    }
    final ext = fileName.split('.').last;
    if (category == GarageMediaCategory.document && ext != 'pdf') {
      throw const FormatException('Only PDF documents are supported');
    }
    if (category == GarageMediaCategory.photo && ext == 'pdf') {
      throw const FormatException('Only photos are supported');
    }
    return '$root/$fileName';
  }
}

class GarageMediaRepository {
  const GarageMediaRepository(this.client);
  final SupabaseClient client;

  void _requireSignIn() {
    if (client.auth.currentUser == null) {
      throw StateError('Garage login required');
    }
  }

  /// Only uploads new immutable files; no upsert/overwrite permitted.
  Future<String> upload({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
    required String mime,
    required Uint8List data,
  }) async {
    _requireSignIn();
    final path = GarageMediaPaths.createUploadPath(
      workspaceId: workspaceId, orderId: orderId, category: category,
      mime: mime, fileSize: data.length,
    );
    await client.storage.from(GarageMediaPaths.bucket).uploadBinary(
      path, data,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );
    return path;
  }

  /// Returns private object names only. Never expose signed/public URLs.
  Future<List<String>> listFileNames({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
  }) async {
    _requireSignIn();
    final dir = GarageMediaPaths.folder(
      workspaceId: workspaceId, orderId: orderId, category: category,
    );
    final files = await client.storage.from(GarageMediaPaths.bucket)
        .list(path: dir);
    final result = <String>[];
    for (final file in files) {
      try {
        GarageMediaPaths.validatedPath(
          workspaceId: workspaceId, orderId: orderId,
          category: category, fileName: file.name,
        );
        result.add(file.name);
      } on FormatException {
        // Hide unexpected MIME/file objects.
      } on ArgumentError {
        // Ignore pseudo-folders and noncanonical paths.
      }
    }
    return List.unmodifiable(result);
  }

  /// Authenticated download fetches latest permissions on EVERY request.
  Future<Uint8List> download({
    required String workspaceId,
    required String orderId,
    required GarageMediaCategory category,
    required String fileName,
  }) async {
    _requireSignIn();
    final path = GarageMediaPaths.validatedPath(
      workspaceId: workspaceId, orderId: orderId,
      category: category, fileName: fileName,
    );
    return client.storage.from(GarageMediaPaths.bucket).download(path);
  }
}

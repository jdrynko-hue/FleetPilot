import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';

import 'media_repository.dart';

/// Saving is a deliberate user export from private Storage, not a public URL.
/// A saved file is outside Garage access revocation; remind operators that
/// exported documents remain on the user's device.
class GaragePdfSaver {
  const GaragePdfSaver._();

  static final _name = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
    r'[0-9a-f]{4}-[0-9a-f]{12}\.pdf$',
  );

  static String baseName(String fileName) {
    if (!_name.hasMatch(fileName)) {
      throw ArgumentError.value(
        fileName, 'fileName', 'Only canonical Garage PDF filenames allowed',
      );
    }
    return fileName.substring(0, fileName.length - 4);
  }

  static void validateBytes(Uint8List bytes) {
    if (bytes.length < 5 || bytes.length > GarageMediaPaths.maxFileBytes ||
        bytes[0] != 0x25 || bytes[1] != 0x50 || bytes[2] != 0x44 ||
        bytes[3] != 0x46 || bytes[4] != 0x2D) {
      throw const FormatException('Invalid or oversized Garage PDF');
    }
  }
}

/// Saves already-authenticated bytes to the user's own device.
///
/// In mobile Safari (Flutter Web) file_saver 0.3.x supports saveFile(), not
/// saveAs(). In native iOS/Android, saveAs() offers the system's save dialog.
/// Neither branch constructs signed/public Storage URLs.
Future<void> saveGaragePdfToDevice(
  String fileName,
  Uint8List bytes,
) async {
  final name = GaragePdfSaver.baseName(fileName);
  GaragePdfSaver.validateBytes(bytes);

  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  } else {
    // Canceling the platform save dialog is a valid no-op.
    await FileSaver.instance.saveAs(
      name: name,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}

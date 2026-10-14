import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/garage/media_repository.dart';

void main() {
  const workspace = '00000000-0000-4000-8000-000000000101';
  const order = '00000000-0000-4000-8000-000000000401';

  test('generates unique cryptographically random photo filenames', () {
    final a = GarageMediaPaths.createUploadPath(
      workspaceId: workspace, orderId: order,
      category: GarageMediaCategory.photo,
      mime: 'image/jpeg', fileSize: 2048,
    );
    final b = GarageMediaPaths.createUploadPath(
      workspaceId: workspace, orderId: order,
      category: GarageMediaCategory.photo,
      mime: 'image/jpeg', fileSize: 2048,
    );
    expect(a, isNot(b));
    expect(a, startsWith('$workspace/$order/photos/'));
    final name = a.split('/').last;
    expect(name, matches(RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
      r'[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$',
    )));
    expect(GarageMediaPaths.validatedPath(
      workspaceId: workspace, orderId: order,
      category: GarageMediaCategory.photo, fileName: name,
    ), a);
  });

  test('only allowlisted photo and document types are accepted', () {
    for (final mime in ['image/png', 'image/jpeg', 'image/webp']) {
      final file = GarageMediaPaths.createUploadPath(
        workspaceId: workspace, orderId: order,
        category: GarageMediaCategory.photo,
        mime: mime, fileSize: 1,
      );
      expect(file, startsWith('$workspace/$order/photos/'));
    }
    final document = GarageMediaPaths.createUploadPath(
      workspaceId: workspace, orderId: order,
      category: GarageMediaCategory.document,
      mime: 'application/pdf', fileSize: 10,
    );
    expect(document, startsWith('$workspace/$order/documents/'));
    expect(document, endsWith('.pdf'));
    for (final invalidMime in ['image/svg+xml', 'text/html', 'application/pdf']) {
      expect(
        () => GarageMediaPaths.extensionFor(
          GarageMediaCategory.photo, invalidMime,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => GarageMediaPaths.extensionFor(
        GarageMediaCategory.document, 'image/png',
      ),
      throwsFormatException,
    );
  });

  test('file sizes are 1 to 5 MiB and checked before upload', () {
    for (final bytes in [0, -1, 5 * 1024 * 1024 + 1]) {
      expect(
        () => GarageMediaPaths.createUploadPath(
          workspaceId: workspace, orderId: order,
          category: GarageMediaCategory.photo,
          mime: 'image/png', fileSize: bytes,
        ),
        throwsRangeError,
      );
    }
    final largestAllowed = GarageMediaPaths.createUploadPath(
      workspaceId: workspace, orderId: order,
      category: GarageMediaCategory.photo,
      mime: 'image/png', fileSize: 5 * 1024 * 1024,
    );
    expect(largestAllowed, endsWith('.png'));
  });

  test('denies object names with traversal, customer PII and wrong extensions',
      () {
    final invalid = [
      '../photos/abc.png',
      'customer@example.com.png',
      'invoice.pdf',
      '../../documents/1.pdf',
      'not-a-uuid.png',
      'ABCD1234.JPG',
    ];
    for (final name in invalid) {
      expect(
        () => GarageMediaPaths.validatedPath(
          workspaceId: workspace, orderId: order,
          category: GarageMediaCategory.photo, fileName: name,
        ),
        throwsArgumentError,
      );
    }
    const example = '00000000-0000-4000-8000-000000000999';
    expect(
      () => GarageMediaPaths.validatedPath(
        workspaceId: workspace, orderId: order,
        category: GarageMediaCategory.photo,
        fileName: '$example.pdf',
      ),
      throwsFormatException,
    );
    expect(
      () => GarageMediaPaths.validatedPath(
        workspaceId: workspace, orderId: order,
        category: GarageMediaCategory.document,
        fileName: '$example.png',
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed workspace and order IDs', () {
    for (final bad in [
      '../../another-shop', 'ABCDEF00-0000-4000-8000-000000000101',
      'shop_id', '',
    ]) {
      expect(
        () => GarageMediaPaths.folder(
          workspaceId: bad, orderId: order,
          category: GarageMediaCategory.photo,
        ),
        throwsArgumentError,
      );
      expect(
        () => GarageMediaPaths.folder(
          workspaceId: workspace, orderId: bad,
          category: GarageMediaCategory.document,
        ),
        throwsArgumentError,
      );
    }
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/media_repository.dart';
import 'package:fleetpilot/garage/order_media_screen.dart';

void main() {
  const png = '00000000-0000-4000-8000-000000000999.png';
  const pdf = '00000000-0000-4000-8000-000000000998.pdf';
  final image = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
    0, 0, 0, 11, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0,
    0, 3, 1, 1, 0, 201, 254, 146, 239, 0, 0, 0, 0, 73, 69, 78,
    68, 174, 66, 96, 130,
  ]);
  setUp(() => AppLocale.language.value = 'en');
  tearDown(() => AppLocale.language.value = 'en');

  Future<void> display(
    WidgetTester tester, {
    required double width,
    required GarageMediaList loadFiles,
    GarageMediaRead? readFile,
    GarageMediaWrite? uploadFile,
    GarageMediaPick? pickFile,
    GaragePdfSave? savePdf,
    bool showDocuments = false,
    bool canUploadPhotos = true,
    bool canUploadDocuments = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: GarageOrderMediaScreen(
        loadFiles: loadFiles,
        readFile: readFile ?? (_, __) async => image,
        uploadFile: uploadFile ?? (_, __, ___) async => 'uploaded',
        pickFile: pickFile ?? (_) async => null,
        savePdf: savePdf ?? (_, __) async {},
        showDocuments: showDocuments,
        canUploadPhotos: canUploadPhotos,
        canUploadDocuments: canUploadDocuments,
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 375.0, 390.0, 900.0]) {
    testWidgets('single-photo view fits width $width and hides financial tab',
        (tester) async {
      await display(tester,
        width: width, loadFiles: (_) async => [png],
      );
      expect(find.text('Repair evidence'), findsOneWidget);
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('PDFs'), findsNothing);
      expect(find.byKey(const Key('garage_media_upload')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('manager can switch to financial documents', (tester) async {
    await display(tester,
      width: 375, showDocuments: true, canUploadDocuments: true,
      loadFiles: (category) async => category == GarageMediaCategory.photo
          ? [png] : [pdf],
    );
    expect(find.text('Photo 1'), findsOneWidget);
    await tester.tap(find.text('PDFs'));
    await tester.pumpAndSettle();
    expect(find.text('PDF document 1'), findsOneWidget);
    expect(find.text('Photo 1'), findsNothing);
  });

  testWidgets('read-only PDF access shows documents without upload', (tester) async {
    await display(tester,
      width: 390, showDocuments: true,
      canUploadPhotos: false, canUploadDocuments: false,
      loadFiles: (_) async => [],
    );
    expect(find.byKey(const Key('garage_media_upload')), findsNothing);
    expect(find.text('No files yet'), findsOneWidget);
  });

  testWidgets('upload permits selected photo and reloads list', (tester) async {
    var count = 0;
    var uploads = 0;
    var selectedCategory = GarageMediaCategory.document;
    await display(tester,
      width: 375,
      loadFiles: (_) async => count == 0 ? [] : [png],
      pickFile: (_) async => GarageSelectedMedia(
        bytes: Uint8List.fromList([1,2,3]), mime:'image/png',
      ),
      uploadFile: (category, mime, bytes) async {
        expect(mime, 'image/png');
        expect(bytes.length, 3);
        selectedCategory = category;
        uploads++;
        count++;
        return 'storage-object';
      },
    );
    await tester.tap(find.byKey(const Key('garage_media_upload')));
    await tester.pumpAndSettle();
    expect(uploads, 1);
    expect(selectedCategory, GarageMediaCategory.photo);
    expect(find.text('Photo 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid upload is rejected before RPC', (tester) async {
    var uploads = 0;
    await display(tester,
      width: 375,
      loadFiles: (_) async => [],
      pickFile: (_) async => GarageSelectedMedia(
        bytes: Uint8List(0), mime: 'image/png',
      ),
      uploadFile: (_, __, ___) async {
        uploads++;
        return 'wrong';
      },
    );
    await tester.tap(find.byKey(const Key('garage_media_upload')));
    await tester.pumpAndSettle();
    expect(uploads, 0);
    expect(find.byKey(const Key('garage_media_error')), findsOneWidget);
  });

  testWidgets('downloaded document is handled as bytes, never a public URL',
      (tester) async {
    String? savedName;
    Uint8List? savedBytes;
    await display(tester,
      width: 390,
      showDocuments: true,
      loadFiles: (category) async =>
          category == GarageMediaCategory.document ? [pdf] : [],
      readFile: (category, name) async {
        expect(category, GarageMediaCategory.document);
        expect(name, pdf);
        return Uint8List.fromList([37,80,68,70]); // PDF signature
      },
      savePdf: (name, bytes) async {
        savedName = name;
        savedBytes = bytes;
      },
    );
    await tester.tap(find.text('PDFs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF document 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_media_save_pdf')), findsOneWidget);
    expect(savedName, isNull, reason: 'Saving requires a fresh user tap');
    await tester.tap(find.byKey(const Key('garage_media_save_pdf')));
    await tester.pumpAndSettle();
    expect(savedName, pdf);
    expect(savedBytes, [37,80,68,70]);
  });

  testWidgets('canceling PDF export retains private bytes', (tester) async {
    var saves = 0;
    await display(tester,
      width: 375,
      showDocuments: true,
      loadFiles: (category) async =>
          category == GarageMediaCategory.document ? [pdf] : [],
      readFile: (_, __) async =>
          Uint8List.fromList([37, 80, 68, 70, 45]),
      savePdf: (_, __) async => saves++,
    );
    await tester.tap(find.text('PDFs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF document 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('revoke access to that copy'), findsOneWidget);
    await tester.tap(find.byKey(const Key('garage_media_cancel_pdf')));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('PDF document 1'), findsOneWidget);
  });

  testWidgets('failed PDF export is handled without an unhandled exception',
      (tester) async {
    await display(tester,
      width: 375,
      showDocuments: true,
      loadFiles: (category) async =>
          category == GarageMediaCategory.document ? [pdf] : [],
      readFile: (_, __) async =>
          Uint8List.fromList([37, 80, 68, 70, 45]),
      savePdf: (_, __) async => throw StateError('Save cancelled by platform'),
    );
    await tester.tap(find.text('PDFs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF document 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('garage_media_save_pdf')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('garage_media_error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed list and failed read show actionable errors', (tester) async {
    await display(tester,
      width: 320,
      loadFiles: (_) async => throw StateError('Denied'),
      readFile: (_, __) async => throw StateError('Denied'),
    );
    expect(find.byKey(const Key('garage_media_error')), findsOneWidget);
    expect(find.byKey(const Key('garage_media_empty')), findsOneWidget);
    expect(find.byKey(const Key('garage_media_item_0')), findsNothing);
  });

  testWidgets('Polish UI has correct navigation and empty state', (tester) async {
    AppLocale.language.value = 'pl';
    await display(tester,
      width: 375, showDocuments: true,
      loadFiles: (_) async => [],
    );
    expect(find.text('Dokumentacja naprawy'), findsOneWidget);
    expect(find.text('Zdjęcia'), findsOneWidget);
    expect(find.text('Brak plików'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleetpilot/core/localization.dart';
import 'package:fleetpilot/garage/media_repository.dart';
import 'package:fleetpilot/garage/order_media_screen.dart';

const photo = '00000000-0000-4000-8000-000000000901.png';
const document = '00000000-0000-4000-8000-000000000902.pdf';
final image = Uint8List.fromList([
  137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1,8,6,0,0,0,
  31,21,196,137,0,0,0,11,73,68,65,84,120,156,99,248,207,192,0,0,3,1,1,0,
  201,254,146,239,0,0,0,0,73,69,78,68,174,66,96,130,
]);
Future<List<String>> files(GarageMediaCategory category) async =>
    category == GarageMediaCategory.photo ? [photo] : [document];
Future<Uint8List> read(GarageMediaCategory category, String name) async =>
    category == GarageMediaCategory.photo ? image : Uint8List.fromList([37,80,68,70]);
Future<String> upload(GarageMediaCategory category, String mime, Uint8List bytes) async => 'ok';
Future<GarageSelectedMedia?> pick(GarageMediaCategory category) async =>
    GarageSelectedMedia(bytes: image, mime: 'image/png');
Future<void> save(String name, Uint8List bytes) async {}

GarageOrderMediaScreen media({GarageMediaList loadFiles = files,
  GarageMediaRead readFile = read, GarageMediaWrite uploadFile = upload,
  GarageMediaPick pickFile = pick, GaragePdfSave savePdf = save,
  bool showDocuments = true, bool canUploadPhotos = true,
  bool canUploadDocuments = false,
}) => GarageOrderMediaScreen(loadFiles: loadFiles, readFile: readFile,
  uploadFile: uploadFile, pickFile: pickFile, savePdf: savePdf,
  showDocuments: showDocuments, canUploadPhotos: canUploadPhotos,
  canUploadDocuments: canUploadDocuments);

Future<void> mount(WidgetTester tester, Widget child, {bool settle = true}) async {
  await tester.pumpWidget(MaterialApp(home: child));
  if (settle) { await tester.pumpAndSettle(); }
  else { await tester.pump(); }
}
Future<void> openPdf(WidgetTester tester) async {
  await tester.tap(find.text('PDFs'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PDF document 1'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppLocale.language.value = 'en';
    final fatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
  });
  tearDown(() => AppLocale.language.value = 'en');

  for (final fails in [false, true]) {
    testWidgets('media ignores old-scope list completion error=$fails', (tester) async {
      final pending = Completer<List<String>>();
      await mount(tester, media(loadFiles: (_) => pending.future), settle: false);
      var loads = 0;
      await mount(tester, media(loadFiles: (_) async { loads++; return []; }));
      if (fails) { pending.completeError(StateError('private old list')); }
      else { pending.complete([photo]); }
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Photo 1'), findsNothing);
      expect(find.byKey(const Key('garage_media_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('media category roundtrip ignores earlier photo list error=$fails', (tester) async {
      final pending = Completer<List<String>>();
      var photos = 0;
      await mount(tester, media(loadFiles: (category) async {
        if (category == GarageMediaCategory.photo && photos++ == 0) return pending.future;
        return [];
      }), settle: false);
      await tester.tap(find.text('PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      if (fails) { pending.completeError(StateError('private old photo list')); }
      else { pending.complete([photo]); }
      await tester.pumpAndSettle();
      expect(photos, 2);
      expect(find.text('Photo 1'), findsNothing);
      expect(find.byKey(const Key('garage_media_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('media upload completion cannot reload new scope error=$fails', (tester) async {
      final pending = Completer<String>();
      var writes = 0;
      await mount(tester, media(uploadFile: (_, mime, bytes) {
        writes++; return pending.future;
      }));
      await tester.tap(find.byKey(const Key('garage_media_upload')));
      await tester.pump();
      expect(writes, 1);
      var loads = 0;
      await mount(tester, media(loadFiles: (_) async { loads++; return [photo]; }));
      if (fails) { pending.completeError(StateError('private old upload')); }
      else { pending.complete('ok'); }
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.byKey(const Key('garage_media_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final pdf in [false, true]) {
      testWidgets('media ignores old ${pdf ? 'PDF' : 'photo'} read error=$fails', (tester) async {
        final pending = Completer<Uint8List>();
        var saves = 0;
        await mount(tester, media(readFile: (_, name) => pending.future,
          savePdf: (_, bytes) async { saves++; }));
        if (pdf) {
          await tester.tap(find.text('PDFs'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(pdf ? 'PDF document 1' : 'Photo 1'));
        await tester.pump();
        await mount(tester, media(loadFiles: (_) async => [], showDocuments: false));
        if (fails) { pending.completeError(StateError('private old bytes')); }
        else { pending.complete(image); }
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(find.byKey(const Key('garage_media_photo_preview')), findsNothing);
        expect(find.byKey(const Key('garage_media_save_pdf')), findsNothing);
        expect(find.byKey(const Key('garage_media_error')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('old PDF save result never pops unrelated route error=$fails', (tester) async {
      final pending = Completer<void>();
      var saves = 0;
      await mount(tester, media(savePdf: (_, bytes) { saves++; return pending.future; }));
      await openPdf(tester);
      final action = tester.widget<FilledButton>(
        find.byKey(const Key('garage_media_save_pdf'))).onPressed!;
      action(); action();
      await tester.pump();
      expect(saves, 1);
      await mount(tester, media(showDocuments: false));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push<void>(MaterialPageRoute<void>(builder: (_) => const Scaffold(
        body: Text('Unrelated destination'))));
      await tester.pumpAndSettle();
      if (fails) { pending.completeError(StateError('private old save')); }
      else { pending.complete(); }
      await tester.pumpAndSettle();
      expect(find.text('Unrelated destination'), findsOneWidget);
      expect(find.byKey(const Key('garage_media_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final downgradeOnly in [false, true]) {
    for (final pdf in [false, true]) {
    testWidgets('pending picker cannot upload after scope/access replacement $downgradeOnly pdf=$pdf', (tester) async {
      final pending = Completer<GarageSelectedMedia?>();
      var writes = 0;
      var newWrites = 0;
      final GarageMediaWrite write = (_, mime, bytes) async { writes++; return 'ok'; };
      final GarageMediaWrite freshWrite = (_, mime, bytes) async { newWrites++; return 'ok'; };
      final GarageMediaPick picker = (_) => pending.future;
      await mount(tester, media(uploadFile: write, pickFile: picker, canUploadDocuments: pdf));
      if (pdf) {
        await tester.tap(find.text('PDFs'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('garage_media_upload')));
      await tester.pump();
      await mount(tester, media(uploadFile: downgradeOnly ? write : freshWrite,
        pickFile: picker, canUploadPhotos: !downgradeOnly || pdf,
        canUploadDocuments: pdf && !downgradeOnly));
      pending.complete(GarageSelectedMedia(bytes: pdf ? Uint8List.fromList([37,80,68,70]) : image,
        mime: pdf ? 'application/pdf' : 'image/png'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(newWrites, 0);
      expect(find.byKey(const Key('garage_media_error')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    }
  }

  for (final pdf in [false, true]) {
    testWidgets('scope replacement closes owned preview without popping another dialog pdf=$pdf', (tester) async {
      var saves = 0;
      await mount(tester, media(savePdf: (_, bytes) async { saves++; }));
      VoidCallback? oldSave;
      if (pdf) {
        await openPdf(tester);
        oldSave = tester.widget<FilledButton>(find.byKey(
          const Key('garage_media_save_pdf'))).onPressed!;
      } else {
        await tester.tap(find.text('Photo 1'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('garage_media_photo_preview')), findsOneWidget);
      }
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push<void>(DialogRoute<void>(context: navigator.context,
        builder: (_) => const AlertDialog(content: Text('Unrelated dialog'))));
      await tester.pumpAndSettle();
      await mount(tester, media(showDocuments: false, canUploadPhotos: false));
      oldSave?.call();
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      expect(find.byKey(const Key('garage_media_photo_preview'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('garage_media_save_pdf'), skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final refreshOnly in [false, true]) {
    testWidgets('stale tile cannot open identical name after replacement $refreshOnly', (tester) async {
      var reads = 0;
      final GarageMediaRead reader = (_, name) async { reads++; return image; };
      await mount(tester, media(readFile: reader));
      final oldTap = tester.widget<ListTile>(find.byKey(
        const Key('garage_media_item_0'))).onTap!;
      if (refreshOnly) {
        await tester.tap(find.byKey(const Key('garage_media_refresh')));
        await tester.pumpAndSettle();
      } else {
        await mount(tester, media(readFile: reader, canUploadPhotos: false));
      }
      oldTap();
      await tester.pumpAndSettle();
      expect(reads, 0);
      await tester.tap(find.text('Photo 1'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final barrier in [false, true]) {
    testWidgets('dismissed PDF save callback cannot export bytes barrier=$barrier', (tester) async {
      var saves = 0;
      await mount(tester, media(savePdf: (_, bytes) async { saves++; }));
      await openPdf(tester);
      final action = tester.widget<FilledButton>(find.byKey(
        const Key('garage_media_save_pdf'))).onPressed!;
      if (barrier) {
        await tester.tapAt(const Offset(8, 80));
      } else {
        await tester.tap(find.byKey(const Key('garage_media_cancel_pdf')));
      }
      action();
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.byKey(const Key('garage_media_save_pdf')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale upload button cannot start a new-scope picker', (tester) async {
    var picks = 0;
    final GarageMediaPick picker = (_) async { picks++; return null; };
    await mount(tester, media(pickFile: picker));
    final oldTap = tester.widget<FloatingActionButton>(find.byKey(
      const Key('garage_media_upload'))).onPressed!;
    await mount(tester, media(pickFile: picker, canUploadDocuments: true));
    oldTap();
    await tester.pumpAndSettle();
    expect(picks, 0);
    await tester.tap(find.byKey(const Key('garage_media_upload')));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed media picker never writes selected bytes', (tester) async {
    final pending = Completer<GarageSelectedMedia?>();
    var writes = 0;
    await mount(tester, media(pickFile: (_) => pending.future,
      uploadFile: (_, mime, bytes) async { writes++; return 'ok'; }));
    await tester.tap(find.byKey(const Key('garage_media_upload')));
    await tester.pump();
    await mount(tester, const SizedBox.shrink());
    pending.complete(GarageSelectedMedia(bytes: image, mime: 'image/png'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}

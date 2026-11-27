import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/reel_upload_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/services/reel_upload_service.dart';
import 'package:ghosst/theme.dart';

class _FakePicker extends FilePicker {
  _FakePicker(this.files);
  final List<PlatformFile> files;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult(files);
}

ReelUploadTicket _ticket({
  DateTime? expiresAt,
  List<ReelImageUploadTicket>? uploads,
}) => ReelUploadTicket(
  reelId: '11111111-1111-4111-8111-111111111111',
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
  uploads:
      uploads ??
      [
        ReelImageUploadTicket(
          position: 1,
          uploadUrl: 'https://video.example/upload.php',
          token: 'signed',
          sha256: 'a' * 64,
          storageKey: 'r1-1.jpg',
          maxBytes: 10485760,
        ),
      ],
);

void main() {
  test('upload guard rejects bad image count/type/size/hash', () {
    final valid = [
      ReelDraftImage(
        path: 'a.jpg',
        fileName: 'a.jpg',
        sizeBytes: 10,
        sha256: 'a' * 64,
        mimeType: 'image/jpeg',
      ),
    ];
    expect(ReelUploadService.validateImages(valid, totalMaxBytes: 52428800), isNull);
    expect(ReelUploadService.validateImages(const [], totalMaxBytes: 52428800), isNotNull);
    expect(
      ReelUploadService.validateImages(
        List.generate(
          6,
          (i) => ReelDraftImage(
            path: '$i.jpg',
            fileName: '$i.jpg',
            sizeBytes: 10,
            sha256: 'a' * 64,
            mimeType: 'image/jpeg',
          ),
        ),
        totalMaxBytes: 52428800,
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateImages(
        [valid.single.copyWith(fileName: 'a.gif', mimeType: 'image/gif', path: 'a.gif')],
        totalMaxBytes: 52428800,
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateImages(
        [valid.single.copyWith(sizeBytes: 10485761)],
        totalMaxBytes: 52428800,
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateImages(
        [valid.single.copyWith(sha256: 'bad')],
        totalMaxBytes: 52428800,
      ),
      isNotNull,
    );
  });

  test('upload guard rejects ticket mismatch and expired ticket before network', () {
    final draft = [
      ReelDraftImage(
        path: 'a.jpg',
        fileName: 'a.jpg',
        sizeBytes: 10,
        sha256: 'a' * 64,
        mimeType: 'image/jpeg',
      ),
    ];
    expect(
      ReelUploadService.validateTicket(draft, _ticket(uploads: const [])),
      isNotNull,
    );
    expect(
      ReelUploadService.validateTicket(
        draft,
        _ticket(expiresAt: DateTime.now().subtract(const Duration(seconds: 1))),
      ),
      isNotNull,
    );
  });

  test('ReelUploadDraft keeps stable base key across caption change', () {
    final draft = ReelUploadDraft(
      caption: 'First',
      images: const [],
      idempotencyBase: 'stable-key',
    );
    final changed = draft.copyWith(caption: 'Second');
    expect(changed.idempotencyBase, draft.idempotencyBase);
  });

  test('SHA-256 helper hashes file bytes', () async {
    final dir = await Directory.systemTemp.createTemp('ghosst-reel-test-');
    try {
      final file = File('${dir.path}/clip.jpg');
      await file.writeAsBytes([1, 2, 3]);
      expect(
        await ReelUploadService.sha256File(file.path),
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('upload rejects bad/too many images before the API', (tester) async {
    for (final files in [
      [PlatformFile(name: 'clip.gif', size: 3, path: 'clip.gif')],
      List.generate(6, (i) => PlatformFile(name: '$i.jpg', size: 3, path: '$i.jpg')),
    ]) {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReelUploadScreen(
            picker: _FakePicker(files),
            prepareUpload: (_) async {
              called = true;
              return _ticket();
            },
            submitUpload: (_, _) async {},
          ),
        ),
      );
      await tester.tap(find.textContaining('Choose'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(called, isFalse);
    }
  });

  testWidgets('successful multi-image submit calls prepare/submit once with ordered images', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ghosst-reel-ui-');
    try {
      final f1 = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      final f2 = File('${dir.path}/b.png')..writeAsBytesSync([4, 5, 6]);
      ReelUploadDraft? prepared;
      ReelUploadDraft? submittedDraft;
      ReelUploadTicket? submittedTicket;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ReelUploadScreen(
            picker: _FakePicker([
              PlatformFile(name: 'a.jpg', size: 3, path: f1.path),
              PlatformFile(name: 'b.png', size: 3, path: f2.path),
            ]),
            prepareUpload: (draft) async {
              prepared = draft;
              return _ticket(
                uploads: [
                  ReelImageUploadTicket(
                    position: 1,
                    uploadUrl: 'https://z/upload.php',
                    token: 't1',
                    sha256: draft.images[0].sha256,
                    storageKey: 'r1-1.jpg',
                    maxBytes: 10485760,
                  ),
                  ReelImageUploadTicket(
                    position: 2,
                    uploadUrl: 'https://z/upload.php',
                    token: 't2',
                    sha256: draft.images[1].sha256,
                    storageKey: 'r1-2.png',
                    maxBytes: 10485760,
                  ),
                ],
              );
            },
            submitUpload: (draft, ticket) async {
              submittedDraft = draft;
              submittedTicket = ticket;
            },
          ),
        ),
      );
      await tester.tap(find.textContaining('Choose'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      var selected = false;
      for (var i = 0; i < 50 && !selected; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        selected = find.text('2 image(s) selected').evaluate().isNotEmpty;
      }
      expect(selected, isTrue);
      await tester.tap(find.text('Post reel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(prepared, isNotNull);
      expect(submittedDraft, isNotNull);
      expect(submittedTicket, isNotNull);
      expect(prepared!.images.map((i) => i.fileName), ['a.jpg', 'b.png']);
      expect(submittedDraft!.images.map((i) => i.fileName), ['a.jpg', 'b.png']);
    } finally {
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          try {
            await dir.delete(recursive: true);
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        await dir.delete(recursive: true);
      });
    }
  });
}

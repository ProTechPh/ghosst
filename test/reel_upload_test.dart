import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/services/reel_upload_service.dart';

ReelUploadTicket _ticket({
  DateTime? expiresAt,
  int maxBytes = 52428800,
  required String sha256,
}) => ReelUploadTicket(
  reelId: '11111111-1111-4111-8111-111111111111',
  uploadUrl: 'https://video.example/upload.php',
  token: 'signed',
  expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
  maxBytes: maxBytes,
  sha256: sha256,
);

void main() {
  test('upload guard rejects empty and oversized files before network', () {
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 0,
        sha256: 'a' * 64,
        ticket: _ticket(sha256: 'a' * 64),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 52428801,
        sha256: 'a' * 64,
        ticket: _ticket(sha256: 'a' * 64),
      ),
      isNotNull,
    );
  });

  test('upload guard rejects non-MP4, malformed hash, and expired tickets', () {
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mov',
        sizeBytes: 10,
        sha256: 'a' * 64,
        ticket: _ticket(sha256: 'a' * 64),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 10,
        sha256: 'bad',
        ticket: _ticket(sha256: 'a' * 64),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 10,
        sha256: 'a' * 64,
        ticket: _ticket(
          sha256: 'a' * 64,
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ),
      isNotNull,
    );
  });

  test('upload guard accepts a valid MP4 ticket', () {
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 10,
        sha256: 'a' * 64,
        ticket: _ticket(sha256: 'a' * 64),
      ),
      isNull,
    );
  });

  test('SHA-256 helper hashes file bytes', () async {
    final dir = await Directory.systemTemp.createTemp('ghosst-reel-test-');
    try {
      final file = File('${dir.path}/clip.mp4');
      await file.writeAsBytes([1, 2, 3]);
      expect(
        await ReelUploadService.sha256File(file.path),
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

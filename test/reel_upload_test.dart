import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/services/reel_upload_service.dart';

ReelUploadTicket _ticket({DateTime? expiresAt, int maxBytes = 52428800}) =>
    ReelUploadTicket(
      reelId: '11111111-1111-4111-8111-111111111111',
      uploadUrl: 'https://video.example/upload.php',
      token: 'signed',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
      maxBytes: maxBytes,
      sha256: 'a' * 64,
    );

void main() {
  test('upload guard rejects empty and oversized files before network', () {
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 0,
        sha256: 'a' * 64,
        ticket: _ticket(),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 52428801,
        sha256: 'a' * 64,
        ticket: _ticket(),
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
        ticket: _ticket(),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 10,
        sha256: 'bad',
        ticket: _ticket(),
      ),
      isNotNull,
    );
    expect(
      ReelUploadService.validateInput(
        filePath: 'video.mp4',
        sizeBytes: 10,
        sha256: 'a' * 64,
        ticket: _ticket(
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
        ticket: _ticket(),
      ),
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_config.dart';
import 'package:ghosst/services/distribution.dart';
import 'package:ghosst/services/install_id.dart';
import 'package:ghosst/services/play_store.dart';
import 'package:ghosst/services/push.dart';
import 'package:ghosst/services/worker_backend.dart';

void main() {
  group('ApiConfig', () {
    test('has a base URL and positive timeouts', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
      expect(ApiConfig.connectTimeout.inSeconds, greaterThan(0));
      expect(ApiConfig.receiveTimeout.inSeconds, greaterThan(0));
      expect(ApiConfig.sendTimeout.inSeconds, greaterThan(0));
    });
  });

  test('Backend exposes the FTP product-image uploader', () {
    expect(Backend.uploadProductImage, isNotNull);
  });

  group('Push', () {
    test('canAsk requires splash done', () {
      Push.splashDone = false;
      expect(Push.canAsk, isFalse);
    });
  });

  group('InstallId', () {
    test('concurrent callers all get the same id', () async {
      InstallId.resetForTest();
      // No secure storage in a test, so every call falls back to a random id —
      // the same first-run race that used to hand one phone several ids.
      final ids = await Future.wait(List.generate(3, (_) => InstallId.get()));
      expect(ids.toSet(), hasLength(1));
      expect(ids.first, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('PlayStore', () {
    test('app id matches the Android applicationId', () {
      expect(PlayStore.appId, 'com.astrixtech.ghosst');
    });
  });

  group('Distribution', () {
    test('toggle flips isPlay/isDirect and store visibility stays on', () {
      Distribution.setPlayForTesting(false);
      expect(Distribution.isDirect, isTrue);
      expect(Distribution.isPlay, isFalse);
      expect(Distribution.showsDownloadStore, isTrue);
      Distribution.setPlayForTesting(true);
      expect(Distribution.isPlay, isTrue);
    });
  });

  group('Backend pure helpers', () {
    test('productThumbUrl returns empty for no images', () {
      expect(Backend.productThumbUrl(const []), '');
      expect(
          Backend.productThumbUrl(
              ['https://cdn/x.png'], ),
          'https://cdn/x.png');
    });

    test('imageUrl passes links through and resolves relative keys', () {
      expect(Backend.imageUrl('https://cdn/x.png'), 'https://cdn/x.png');
      final resolved = Backend.imageUrl('uploads/covers/a.jpg');
      expect(resolved, startsWith('https://'));
      expect(resolved, endsWith('uploads/covers/a.jpg'));
    });

    test('AppUser holds its fields', () {
      const u = AppUser(
        id: 'u1',
        email: 'a@b.co',
        name: 'Ana',
        photoUrl: 'https://example.com/p.jpg',
        chatMuted: true,
      );
      expect(u.id, 'u1');
      expect(u.chatMuted, isTrue);
      expect(u.createdAt, '');
      expect(u.photoUrl, 'https://example.com/p.jpg');
    });
  });
}

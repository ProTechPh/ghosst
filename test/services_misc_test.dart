import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_config.dart';
import 'package:ghosst/services/cloudinary.dart';
import 'package:ghosst/services/distribution.dart';
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

  group('CloudinaryUpload', () {
    test('unsigned preset constants are set', () {
      expect(CloudinaryUpload.cloudName, isNotEmpty);
      expect(CloudinaryUpload.uploadPreset, isNotEmpty);
    });

    test('exception message survives toString', () {
      expect(const CloudinaryException('nope').toString(), 'nope');
    });
  });

  group('Push', () {
    test('configured reflects the app id', () {
      expect(Push.configured, Push.appId.isNotEmpty);
      expect(Push.appId, isNotEmpty);
    });

    test('canAsk requires splash done', () {
      Push.splashDone = false;
      expect(Push.canAsk, isFalse);
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

    test('imageUrl passes links through', () {
      expect(Backend.imageUrl('https://cdn/x.png'), 'https://cdn/x.png');
      expect(Backend.imageUrl('abc'), 'abc');
    });

    test('AppUser holds its fields', () {
      const u = AppUser(id: 'u1', email: 'a@b.co', name: 'Ana', chatMuted: true);
      expect(u.id, 'u1');
      expect(u.chatMuted, isTrue);
      expect(u.createdAt, '');
    });
  });
}

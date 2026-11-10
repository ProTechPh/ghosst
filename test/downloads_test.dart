import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/apk_download.dart';
import 'package:ghosst/services/download_service.dart';
import 'package:ghosst/services/mediafire.dart';

void main() {
  group('MediaFire.needsResolve', () {
    test('share pages need resolving', () {
      expect(
          MediaFire.needsResolve('https://www.mediafire.com/file/abc/file'),
          isTrue);
      expect(MediaFire.needsResolve('HTTP://MEDIAFIRE.COM/file/x/file'), isTrue);
    });

    test('direct CDN links and third-party hosts do not', () {
      expect(
          MediaFire.needsResolve(
              'https://download12.mediafire.com/abc/file.apk'),
          isFalse);
      expect(MediaFire.needsResolve('https://example.com/file/x/file.apk'),
          isFalse);
      expect(MediaFire.needsResolve(''), isFalse);
      expect(MediaFire.needsResolve('   '), isFalse);
      // Folder pages without a file key cannot be resolved.
      expect(MediaFire.needsResolve('https://www.mediafire.com/folder/abc'),
          isFalse);
    });

    test('resolveDirectUrl rejects an empty link without network', () async {
      await expectLater(MediaFire.resolveDirectUrl(''),
          throwsA(isA<MediaFireException>()));
    });

    test('direct links pass through unchanged', () async {
      const url = 'https://download12.mediafire.com/abc/file.apk';
      expect(await MediaFire.resolveDirectUrl(url), url);
      const third = 'https://example.com/file.apk';
      expect(await MediaFire.resolveDirectUrl(third), third);
    });
  });

  group('DownloadService.nameFromUrl', () {
    test('takes the last dotted segment', () {
      expect(
          DownloadService.nameFromUrl(
              'https://cdn.example.com/a/b/app.apk'),
          'app.apk');
      expect(
          DownloadService.nameFromUrl(
              'https://cdn.example.com/file.tar.gz'),
          'file.tar.gz');
    });

    test('falls back when there is no dotted segment', () {
      expect(DownloadService.nameFromUrl('https://cdn.example.com/download'),
          'download');
      expect(DownloadService.nameFromUrl('not a url'), 'download');
      expect(DownloadService.nameFromUrl(''), 'download');
    });

    test('sanitises path separators', () {
      expect(
          DownloadService.nameFromUrl('https://cdn.example.com/a%2Fb.apk'),
          'a_b.apk');
    });
  });

  group('DownloadProgress.fraction', () {
    test('clamps and hides when total is unknown', () {
      expect(
          const DownloadProgress(received: 50, total: 100, speed: 0, label: 'x')
              .fraction,
          0.5);
      expect(
          const DownloadProgress(received: 0, total: 0, speed: 0, label: 'x')
              .fraction,
          isNull);
      expect(
          const DownloadProgress(received: 150, total: 100, speed: 0, label: 'x')
              .fraction,
          1.0);
    });
  });

  group('ApkDownloadState', () {
    test('done / failed / fraction', () {
      expect(const ApkDownloadState(state: 'successful').done, isTrue);
      expect(const ApkDownloadState(state: 'running').done, isFalse);
      expect(const ApkDownloadState(state: 'failed').failed, isTrue);
      expect(const ApkDownloadState(state: 'missing').failed, isTrue);
      expect(const ApkDownloadState(state: 'error').failed, isTrue);
      expect(const ApkDownloadState(state: 'running').failed, isFalse);
      expect(
          const ApkDownloadState(state: 'running', received: 25, total: 100)
              .fraction,
          0.25);
      expect(const ApkDownloadState(state: 'running').fraction, isNull);
      expect(ApkDownloadState.unknown.state, 'error');
    });

    test('OfficialApk.start rejects invalid links without a channel', () async {
      await expectLater(OfficialApk.start(url: '', name: 'x.apk'),
          throwsA(isA<DownloadLinkException>()));
      await expectLater(
          OfficialApk.start(url: 'ftp://example.com/x.apk', name: 'x.apk'),
          throwsA(isA<DownloadLinkException>()));
    });
  });
}

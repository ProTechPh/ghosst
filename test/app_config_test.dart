import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('update gate blocks only installs below the published minimum', () {
    const cfg = AppConfig(
      minVersionCode: 55,
      latestVersionCode: 55,
      playUrl: 'play',
      directUrl: 'direct',
    );
    expect(cfg.blocks(54), isTrue);
    expect(cfg.blocks(55), isFalse);
    expect(cfg.blocks(56), isFalse);
  });

  test('a zero minimum disables the gate', () {
    const cfg = AppConfig(
      minVersionCode: 0,
      latestVersionCode: 0,
      playUrl: '',
      directUrl: '',
    );
    expect(cfg.blocks(1), isFalse);
  });

  test('update url follows the distribution', () {
    const cfg = AppConfig(
      minVersionCode: 1,
      latestVersionCode: 2,
      playUrl: 'play',
      directUrl: 'direct',
    );
    expect(cfg.updateUrl(isPlay: true), 'play');
    expect(cfg.updateUrl(isPlay: false), 'direct');
  });
}

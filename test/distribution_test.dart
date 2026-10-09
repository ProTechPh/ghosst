import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/distribution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download store is available in direct builds', () {
    Distribution.setPlayForTesting(false);
    expect(Distribution.showsDownloadStore, isTrue);
    Distribution.setPlayForTesting(true);
  });

  test('Play builds respect the explicit download-store flag', () {
    Distribution.setPlayForTesting(true);
    const enabled = bool.fromEnvironment(
      'ENABLE_DOWNLOAD_STORE',
      defaultValue: false,
    );
    expect(Distribution.showsDownloadStore, enabled);
  });
}

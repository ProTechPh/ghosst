import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/distribution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('download store is available in direct builds', () {
    Distribution.setPlayForTesting(false);
    expect(Distribution.showsDownloadStore, isTrue);
    Distribution.setPlayForTesting(true);
  });

  test('download store is available in Play builds', () {
    Distribution.setPlayForTesting(true);
    expect(Distribution.showsDownloadStore, isTrue);
  });
}

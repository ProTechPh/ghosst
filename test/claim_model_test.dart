import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/backend.dart';

// The Worker writes the product type ('app') into a download claim's keyText
// and leaves the URL out of the row, so `isDownload` cannot rely on the URL
// alone — a failed download ticket used to turn a purchase into a fake key.
void main() {
  Claim claim({String keyText = '', String downloadUrl = ''}) => Claim(
    id: 'c1',
    productId: 'p1',
    productName: 'Product',
    keyText: keyText,
    cost: 10,
    createdAt: '2026-01-01T00:00:00Z',
    downloadUrl: downloadUrl,
  );

  test('a download claim stays a download when its link is missing', () {
    expect(claim(keyText: 'app').isDownload, isTrue);
  });

  test('apk and file claims are downloads too', () {
    expect(claim(keyText: 'apk').isDownload, isTrue);
    expect(claim(keyText: 'file').isDownload, isTrue);
  });

  test('a license key is not a download', () {
    expect(claim(keyText: 'XXXX-YYYY-ZZZZ-1111').isDownload, isFalse);
  });

  test('a link alone is enough', () {
    expect(claim(downloadUrl: 'https://www.mediafire.com/file/x').isDownload, isTrue);
  });
}

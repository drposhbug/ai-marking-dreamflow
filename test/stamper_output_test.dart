import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/test_stamper.dart';

/// Builds a real PDF and checks the things that would embarrass us in front
/// of a class: file size, and that copies reuse one embedded image rather
/// than one per copy.
void main() {
  test('30 copies of a 3-page test stay a sane file size', () async {
    // Stand-in page images at roughly the size a 2800px render produces.
    final page = File('test/fixtures/page.jpg');
    if (!page.existsSync()) {
      markTestSkipped('no fixture image; run the generator test locally');
      return;
    }
    final bytes = page.readAsBytesSync();
    final pdf = await TestStamper.build(
      pageImages: [bytes, bytes, bytes],
      testCode: 'AB12',
      copies: 30,
    );
    // 90 printed pages. If each copy re-embedded its images this would run
    // to hundreds of MB; sharing them keeps it near the size of 3 images.
    expect(pdf.length, lessThan(12 * 1024 * 1024),
        reason: 'PDF is ${(pdf.length / 1024 / 1024).toStringAsFixed(1)}MB — images are probably not being shared across copies');
    expect(pdf.length, greaterThan(1000));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-facing Dart source contains no mojibake markers', () {
    final source = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final marker in ['Ã', 'Â', 'â€', '�']) {
      expect(source, isNot(contains(marker)),
          reason: 'Found corrupted text marker: $marker');
    }
  });
}

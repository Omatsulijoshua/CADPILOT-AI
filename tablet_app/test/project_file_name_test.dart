import 'package:cadpilot_tablet/src/project_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a portable filename from a project name', () {
    expect(
      portableProjectFileName('  Workshop cabinet / v2  '),
      'Workshop_cabinet_v2.cadpilot.json',
    );
  });

  test('uses a safe fallback and bounds long filenames', () {
    expect(portableProjectFileName(' /// '), 'cadpilot_project.cadpilot.json');
    final fileName = portableProjectFileName('a' * 200);
    expect(fileName, endsWith('.cadpilot.json'));
    expect(fileName.length, lessThanOrEqualTo(95));
  });
}

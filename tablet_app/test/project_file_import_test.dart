import 'package:cadpilot_tablet/src/project_file_export.dart';
import 'package:cadpilot_tablet/src/project_file_import.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cadpilot/files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('forwards a portable project picker request to the native host',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickProjectManifest');
      return '{"schemaVersion":1}';
    });

    expect(await importProjectFile(), '{"schemaVersion":1}');
  });

  test('forwards portable project content to the native save dialog', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveProjectManifest');
      expect(call.arguments, {
        'content': '{"schemaVersion":1}',
        'fileName': 'workshop.cadpilot.json',
      });
      return 'Project manifest saved to the selected location.';
    });

    expect(
      await exportProjectFile(
        content: '{"schemaVersion":1}',
        fileName: 'workshop.cadpilot.json',
      ),
      'Project manifest saved to the selected location.',
    );
  });
}

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
}

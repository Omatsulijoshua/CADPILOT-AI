import 'package:cadpilot_tablet/src/spatial.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadpilot/ar-runtime-install-test');
  const service = SpatialCapabilityService(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps every native AR runtime install outcome', () async {
    const expectations = {
      'installed': ArRuntimeInstallResult.installed,
      'install_requested': ArRuntimeInstallResult.installRequested,
      'declined': ArRuntimeInstallResult.declined,
      'unexpected': ArRuntimeInstallResult.unavailable,
    };
    for (final entry in expectations.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => entry.key);
      expect(await service.requestArRuntimeInstall(), entry.value);
    }
  });

  test('uses the dedicated native runtime installation method', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'install_requested';
    });
    expect(await service.requestArRuntimeInstall(),
        ArRuntimeInstallResult.installRequested);
    expect(received?.method, 'requestArRuntimeInstall');
    expect(received?.arguments, isNull);
  });

  test('platform errors fail closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ar_runtime_install_unavailable');
    });
    expect(await service.requestArRuntimeInstall(),
        ArRuntimeInstallResult.unavailable);
  });

  test('missing native host fails closed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException();
    });
    expect(await service.requestArRuntimeInstall(),
        ArRuntimeInstallResult.unavailable);
  });
}

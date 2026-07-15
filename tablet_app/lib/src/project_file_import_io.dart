import 'package:flutter/services.dart';

const _filesChannel = MethodChannel('cadpilot/files');

Future<String?> importProjectFile() async {
  try {
    return await _filesChannel.invokeMethod<String>('pickProjectManifest');
  } on MissingPluginException {
    throw UnsupportedError(
      'Project manifest import is not available on this platform.',
    );
  }
}

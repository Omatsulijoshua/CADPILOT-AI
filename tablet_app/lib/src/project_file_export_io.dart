import 'package:flutter/services.dart';

const _filesChannel = MethodChannel('cadpilot/files');

Future<String> exportProjectFile({
  required String content,
  required String fileName,
}) async =>
    await _filesChannel.invokeMethod<String>('saveProjectManifest', {
      'content': content,
      'fileName': fileName,
    }) ??
    'Project manifest saved.';

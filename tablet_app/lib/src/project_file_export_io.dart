import 'package:flutter/services.dart';

import 'project_file_errors.dart';

const _filesChannel = MethodChannel('cadpilot/files');

Future<String> exportProjectFile({
  required String content,
  required String fileName,
}) async {
  try {
    return await _filesChannel.invokeMethod<String>('saveProjectManifest', {
          'content': content,
          'fileName': fileName,
        }) ??
        'Project manifest saved.';
  } on PlatformException catch (error) {
    if (error.code == 'project_manifest_save_cancelled') {
      throw const ProjectFileOperationCancelled();
    }
    rethrow;
  }
}

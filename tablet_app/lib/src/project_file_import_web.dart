// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

Future<String?> importProjectFile() async {
  final input = html.FileUploadInputElement()
    ..accept = '.json,.cadpilot.json,application/json';
  input.click();
  await input.onChange.first;
  final file = input.files?.singleOrNull;
  if (file == null) return null;
  final reader = html.FileReader();
  final completed = Completer<void>();
  reader.onLoadEnd.listen((_) => completed.complete());
  reader.readAsText(file);
  await completed.future;
  return reader.result as String?;
}

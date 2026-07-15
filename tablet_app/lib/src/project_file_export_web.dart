// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<String> exportProjectFile({
  required String content,
  required String fileName,
}) async {
  final blob = html.Blob([content], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none'
    ..click();
  html.Url.revokeObjectUrl(url);
  return 'Project manifest download started: $fileName';
}

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

Future<String> exportStlFile({
  required String content,
  required String fileName,
}) async {
  final blob = html.Blob([content], 'model/stl');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none'
    ..click();
  html.Url.revokeObjectUrl(url);
  return 'STL download started: $fileName';
}

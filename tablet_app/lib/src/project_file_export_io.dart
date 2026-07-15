import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> exportProjectFile({
  required String content,
  required String fileName,
}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(content, flush: true);
  return 'Project manifest saved to ${file.path}';
}

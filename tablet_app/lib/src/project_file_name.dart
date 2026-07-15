String portableProjectFileName(String projectName) {
  final normalized = projectName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final stem = normalized.isEmpty
      ? 'cadpilot_project'
      : normalized.substring(
          0, normalized.length > 80 ? 80 : normalized.length);
  return '$stem.cadpilot.json';
}

/// OS-neutral update contract. Downloading never implies installation.
abstract class UpdateBackend {
  Future<InstalledVersion> getInstalledVersion();
  Future<UpdateRelease?> check(InstalledVersion current);
  Future<void> download(
    UpdateRelease release,
    void Function(int received, int? total) onProgress,
  );
  Future<String> install(UpdateRelease release);
  void cancel();
  void dispose();
}

class InstalledVersion {
  const InstalledVersion({
    required this.version,
    required this.build,
    required this.platform,
    this.architecture = '',
  });
  final String version;
  final String build;
  final String platform;
  final String architecture;
  bool get supported => const ['web', 'android', 'macos'].contains(platform);
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.build,
    this.notes = '',
    required this.releasePage,
    this.asset,
  });
  final String version;
  final String build;
  final String notes;
  final Uri releasePage;
  final UpdateAsset? asset;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });
  final String name;
  final Uri url;
  final int size;
  final String sha256;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Numeric stable versions plus strictly increasing native build number.
/// Release tags may have a preview suffix; manifest versions may not.
int compareVersions(String a, String b) {
  List<int> parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$')
        .firstMatch(value);
    if (match == null) throw const FormatException('Invalid version');
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final left = parse(a), right = parse(b);
  for (var i = 0; i < 3; i++) {
    final result = left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return 0;
}

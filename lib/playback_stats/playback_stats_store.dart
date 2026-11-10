abstract interface class PlaybackStatsStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<String> deviceId();

  /// `folder` 表示连接了用户授权的文件夹，是否云同步取决于所选位置。
  /// 没有可访问的同步位置时返回 `local`；网页返回 `browser`。
  Future<String> storageLocation();
}

/// 通过系统选择器授权个人文件夹，不需要开发者 iCloud 容器。
abstract interface class PlaybackStatsFolderStore {
  bool get canPickFolder;
  Future<bool> pickFolder();
}

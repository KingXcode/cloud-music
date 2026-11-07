import '../models.dart';

abstract interface class MusicGateway {
  Stream<LibrarySnapshot> get snapshots;
  Future<LibrarySnapshot> initialize();
  Future<void> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]);
  Future<void> dispose();
}

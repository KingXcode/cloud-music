abstract interface class FilterStore {
  Future<String?> read();
  Future<void> write(String value);
}

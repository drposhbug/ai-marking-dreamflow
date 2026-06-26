class IdFactory {
  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}

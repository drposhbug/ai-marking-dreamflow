class IdFactory {
  /// Rises by one for every id handed out in this run of the app.
  static int _seq = 0;

  /// A new id that is unique no matter how fast it is asked for.
  ///
  /// The timestamp alone is not: the clock advances in steps of about a
  /// millisecond on Windows and inside tests, so a roster import creating
  /// thirty students in a loop hands several of them the SAME id. That is
  /// not a cosmetic clash — marked work is filed against a student id, so
  /// two students sharing one end up with each other's marks in the
  /// gradebook export and in their report card comments, which is the one
  /// mistake this app can never make.
  ///
  /// The counter fixes that regardless of clock resolution. The timestamp
  /// stays in front so an id still says roughly when it was made, but
  /// nothing sorts by id — order comes from createdAt.
  static String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
}

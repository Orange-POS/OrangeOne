import 'dart:math';

/// A short, user-visible reference for one reported technical failure.
///
/// Support asks for it and finds the matching report through the `error_id`
/// key. It is random: it carries no customer, device or session information.
class ErrorReference {
  const new _();

  // No 0/O or 1/I/L, so it can be read out over the phone.
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const prefix = 'OO-';
  static const length = 6;

  static String generate([Random? random]) {
    final source = random ?? Random.secure();
    final code = List.generate(
      length,
      (_) => _alphabet[source.nextInt(_alphabet.length)],
    ).join();
    return '$prefix$code';
  }

  static bool isValid(String value) =>
      RegExp('^$prefix[$_alphabet]{$length}\$').hasMatch(value);
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text that people read (string literals and ARB messages) never names the
/// backend product, and "Powered By" belongs to the Login Home screen only.
void main() {
  final dartFiles = [
    for (final entity in Directory('lib').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.replaceAll(r'\', '/').contains('lib/l10n/gen/'))
        entity,
  ];

  /// String literals of [file] without comments, imports and directives.
  Iterable<String> literals(File file) sync* {
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trimLeft();
      if (line.startsWith('//') ||
          line.startsWith('import ') ||
          line.startsWith('export ') ||
          line.startsWith('part ')) {
        continue;
      }
      for (final match in RegExp(
        r"""'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)" """.trim(),
      ).allMatches(line)) {
        yield match.group(1) ?? match.group(2) ?? '';
      }
    }
  }

  test('no user-facing string names Odoo', () {
    final offenders = <String>[];
    for (final file in dartFiles) {
      for (final text in literals(file)) {
        // ODOO_* are configuration keys, not text shown in the app.
        if (RegExp('odoo', caseSensitive: false).hasMatch(text) &&
            !RegExp(r'^ODOO_[A-Z_]+$').hasMatch(text)) {
          offenders.add('${file.path}: $text');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('no translated message names Odoo', () {
    for (final file in Directory('lib/l10n/arb').listSync().whereType<File>()) {
      final messages = jsonDecode(file.readAsStringSync()) as Map;
      for (final entry in messages.entries) {
        if (entry.value is String) {
          expect(
            (entry.value as String).toLowerCase(),
            isNot(contains('odoo')),
            reason: '${file.path} ${entry.key}',
          );
        }
      }
    }
  });

  test('"Powered By" appears only on the Login Home screen', () {
    final users = [
      for (final file in dartFiles)
        if (file.readAsStringSync().contains('poweredBy') ||
            file.readAsStringSync().contains('Powered By'))
          file.path.replaceAll(r'\', '/'),
    ];
    expect(users, [
      'lib/features/authentication/presentation/pages/login_page.dart',
    ]);
  });
}

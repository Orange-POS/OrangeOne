import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens content in other apps. Never throws: false means nothing opened.
abstract interface class ExternalLauncher {
  /// Opens [uri] only in an installed app that is not a browser (for a
  /// YouTube link, the YouTube app).
  Future<bool> openInApp(Uri uri);

  /// Opens [uri] in the default browser.
  Future<bool> openInBrowser(Uri uri);
}

class UrlExternalLauncher implements ExternalLauncher {
  const new();

  @override
  Future<bool> openInApp(Uri uri) =>
      _launch(uri, LaunchMode.externalNonBrowserApplication);

  @override
  Future<bool> openInBrowser(Uri uri) =>
      _launch(uri, LaunchMode.externalApplication);

  Future<bool> _launch(Uri uri, LaunchMode mode) async {
    try {
      return await launchUrl(uri, mode: mode);
    } on Object {
      // No matching app, or the platform refused.
      return false;
    }
  }
}

final externalLauncherProvider = Provider<ExternalLauncher>(
  (ref) => const UrlExternalLauncher(),
  name: 'externalLauncherProvider',
);

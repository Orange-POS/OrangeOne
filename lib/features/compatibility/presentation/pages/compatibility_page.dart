import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orange_one/core/capabilities/compatibility.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';
import 'package:orange_one/shared/widgets/app_logo.dart';

/// Shown instead of the signed-in screens when the shop's backend cannot be
/// used with this app: the app must be updated, the server is too old, or
/// it is under maintenance. Sign-out always stays available.
class CompatibilityPage extends StatelessWidget {
  const new({
    required this.status,
    required this.onRetry,
    required this.onSignOut,
    super.key,
  });

  final CompatibilityStatus status;

  /// Asks the shop's server again (`GET /meta`).
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, title, body) = switch (status) {
      CompatibilityStatus.appUpgradeRequired => (
        Icons.system_update,
        l10n.compatibilityUpgradeTitle,
        l10n.compatibilityUpgradeBody,
      ),
      CompatibilityStatus.maintenance => (
        Icons.build_circle_outlined,
        l10n.compatibilityMaintenanceTitle,
        l10n.compatibilityMaintenanceBody,
      ),
      CompatibilityStatus.backendUnsupported ||
      CompatibilityStatus.compatible => (
        Icons.dns_outlined,
        l10n.compatibilityUnsupportedTitle,
        l10n.compatibilityUnsupportedBody,
      ),
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: OrangeTheme.dark,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(gradient: OrangeTheme.gradient),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewport.maxHeight - 64,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppLogo(size: 96),
                      const SizedBox(height: 24),
                      Icon(icon, color: Colors.white, size: 40),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          key: const Key('compatibility-title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const Key('compatibility-retry'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          onPressed: onRetry,
                          child: Text(l10n.compatibilityRetry),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('compatibility-sign-out'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          onPressed: onSignOut,
                          child: Text(l10n.compatibilitySignOut),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

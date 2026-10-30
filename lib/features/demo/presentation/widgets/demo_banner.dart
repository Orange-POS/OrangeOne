import 'package:flutter/material.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Strip above every screen while Demo Mode runs. It covers the status bar
/// area, so the screens below keep their own layout.
class DemoBanner extends StatelessWidget {
  const new({required this.onSettings, super.key});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      key: const Key('demo-banner'),
      color: OrangeTheme.actionPressed,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.science_outlined, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.demoBannerText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('demo-banner-settings'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onSettings,
                child: Text(
                  l10n.demoBannerSettings,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

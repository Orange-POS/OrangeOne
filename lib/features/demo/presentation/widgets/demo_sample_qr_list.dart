import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/demo/domain/entities/demo_sample.dart';
import 'package:orange_one/features/demo/presentation/providers/demo_providers.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Sample QR codes shown on the QR login screen while Demo Mode is on. A tap
/// signs into a Demo Mode session; no camera, network or server is involved.
class DemoSampleQrList extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    String title(DemoSample sample) => switch (sample) {
      DemoSample.manager => l10n.demoSampleManagerTitle,
      DemoSample.viewer => l10n.demoSampleViewerTitle,
    };
    String body(DemoSample sample) => switch (sample) {
      DemoSample.manager => l10n.demoSampleManagerBody,
      DemoSample.viewer => l10n.demoSampleViewerBody,
    };
    return ListView(
      key: const Key('demo-sample-qr-list'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          l10n.demoSignInTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.demoSignInBody,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 16),
        for (final sample in DemoSample.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: Key('demo-sample-${sample.id}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    ref.read(demoLoginProvider.notifier).signIn(sample),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.qr_code_2,
                          size: 48,
                          color: OrangeTheme.action,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title(sample),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                body(sample),
                                style: const TextStyle(
                                  color: OrangeTheme.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

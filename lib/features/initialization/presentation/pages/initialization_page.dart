import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/initialization/presentation/providers/initialization_controller.dart';
import 'package:orange_one/shared/widgets/skeleton.dart';

class InitializationPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialization = ref.watch(initializationControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('OrangeONE')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: initialization.when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const Skeleton(
                label: 'Loading application configuration',
                child: SizedBox(width: 240, child: SkeletonLines(count: 3)),
              ),
              data: (environment) => Text(
                'Application initialized\nEnvironment: ${environment.name}',
                textAlign: TextAlign.center,
              ),
              error: (error, stackTrace) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unable to initialize the application. Please try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref
                        .read(initializationControllerProvider.notifier)
                        .retry(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

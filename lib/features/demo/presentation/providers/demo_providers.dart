import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orange_one/features/demo/data/repositories/demo_catalog.dart';
import 'package:orange_one/features/demo/data/repositories/demo_product_details_repository.dart';
import 'package:orange_one/features/demo/data/repositories/demo_product_repository.dart';
import 'package:orange_one/features/demo/domain/entities/demo_sample.dart';
import 'package:orange_one/features/demo/domain/entities/demo_session.dart';
import 'package:orange_one/features/home/data/repositories/recent_scans_repositories.dart';
import 'package:orange_one/features/home/domain/repositories/product_repository.dart';
import 'package:orange_one/features/home/domain/repositories/recent_scans_repository.dart';
import 'package:orange_one/features/products/domain/repositories/product_details_repository.dart';

/// Whether Demo Mode is switched on, or null when it is off.
///
/// Demo Mode is never persisted and never starts by itself: every launch
/// begins in normal mode, and only [DemoModeController.enable] switches it on.
/// Switching it on opens no session: the QR login offers sample QR codes.
final NotifierProvider<DemoModeController, DemoSession?> demoModeProvider =
    NotifierProvider<DemoModeController, DemoSession?>(
      DemoModeController.new,
      name: 'demoModeProvider',
    );

class DemoModeController extends Notifier<DemoSession?> {
  var _runs = 0;

  @override
  DemoSession? build() => null;

  /// Switches Demo Mode on; does nothing while it already is.
  void enable() {
    if (state != null) return;
    state = DemoSession(++_runs);
  }

  /// Switches it off. [demoLoginProvider] and all sample data go with it.
  void disable() => state = null;
}

/// The Demo Mode sign-in, or null while signed out of Demo Mode.
///
/// It is separate from the real `SessionController`: nothing here touches
/// authentication, secure storage or the network.
final NotifierProvider<DemoLoginController, DemoLogin?> demoLoginProvider =
    NotifierProvider<DemoLoginController, DemoLogin?>(
      DemoLoginController.new,
      name: 'demoLoginProvider',
    );

class DemoLoginController extends Notifier<DemoLogin?> {
  var _logins = 0;

  @override
  DemoLogin? build() {
    // Turning Demo Mode off signs out of it.
    ref.watch(demoModeProvider);
    return null;
  }

  /// Signs in with a sample QR code; only while Demo Mode is on.
  void signIn(DemoSample sample) {
    if (ref.read(demoModeProvider) == null || state != null) return;
    state = DemoLogin(++_logins, sample);
  }

  /// Leaves the sample session and discards its data.
  void signOut() => state = null;
}

/// The login's isolated sample inventory; a new one for every sign-in.
final Provider<DemoCatalog> demoCatalogProvider = Provider<DemoCatalog>((ref) {
  ref.watch(demoLoginProvider);
  return DemoCatalog.seeded();
}, name: 'demoCatalogProvider');

final Provider<ProductRepository> demoProductRepositoryProvider =
    Provider<ProductRepository>(
      (ref) => DemoProductRepository(ref.watch(demoCatalogProvider)),
      name: 'demoProductRepositoryProvider',
    );

final Provider<ProductDetailsRepository> demoProductDetailsRepositoryProvider =
    Provider<ProductDetailsRepository>((ref) {
      final canEdit =
          ref.watch(
            demoLoginProvider.select((login) => login?.sample.canEdit),
          ) ??
          false;
      return DemoProductDetailsRepository(
        ref.watch(demoCatalogProvider),
        canEdit: canEdit,
      );
    }, name: 'demoProductDetailsRepositoryProvider');

/// In memory only: the demo's recent scans are gone when the login ends.
final Provider<RecentScansRepository> demoRecentScansRepositoryProvider =
    Provider<RecentScansRepository>((ref) {
      ref.watch(demoLoginProvider);
      return MemoryRecentScansRepository();
    }, name: 'demoRecentScansRepositoryProvider');

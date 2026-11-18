import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:orange_one/core/errors/app_failure.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const new(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Exception {
      throw storageFailure;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Exception {
      throw storageFailure;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Exception {
      throw storageFailure;
    }
  }
}

/// The device's secure storage, also used by the bootstrap before the
/// provider scope exists.
const SecretStore platformSecretStore = PlatformSecretStore(
  FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  ),
);

final secretStoreProvider = Provider<SecretStore>(
  (ref) => platformSecretStore,
  name: 'secretStoreProvider',
);

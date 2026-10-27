import 'dart:math';

/// `DeviceInfo` sent with the QR exchange. The install id binds the refresh
/// token family to this app installation.
class DeviceModel {
  const new({
    required this.installId,
    required this.platform,
    required this.appVersion,
    this.name = 'OrangeONE mobile',
  });

  final String installId;

  /// `android` or `ios`.
  final String platform;
  final String appVersion;
  final String name;

  Map<String, dynamic> toJson() => {
    'install_id': installId,
    'platform': platform,
    'app_version': appVersion,
    'name': name,
  };

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isInstallId(String value) => _uuid.hasMatch(value);

  /// A random UUID v4 for a new installation.
  static String newInstallId([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }

  @override
  String toString() => 'DeviceModel(redacted)';
}

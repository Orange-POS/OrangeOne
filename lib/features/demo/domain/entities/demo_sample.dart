/// A sample QR code offered on the QR login screen while Demo Mode is on.
///
/// It stands in for the QR code of a POS: choosing one signs into a Demo Mode
/// session. It is never parsed as, or sent like, a real login payload.
enum DemoSample {
  manager(id: 'manager', canEdit: true),
  viewer(id: 'viewer', canEdit: false);

  new({required this.id, required this.canEdit});

  final String id;

  /// Whether the sample session may change products, prices and stock.
  final bool canEdit;
}

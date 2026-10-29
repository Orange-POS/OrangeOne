import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/core/network/wifi_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const events = EventChannel('dev.fluttercommunity.plus/connectivity_status');
  late List<String> current;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    current = ['wifi'];
    sink = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(methods, (call) async => current)
          ..setMockStreamHandler(
            events,
            MockStreamHandler.inline(
              onListen: (arguments, events) => sink = events,
            ),
          );
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(methods, null)
        ..setMockStreamHandler(events, null);
    });
  });

  Future<List<bool>> observe(
    ProviderContainer container,
    Future<void> Function() act,
  ) async {
    final seen = <bool>[];
    container.listen(wifiConnectionProvider, (_, next) {
      if (next.hasValue) seen.add(next.requireValue);
    });
    await Future<void>.delayed(Duration.zero);
    await act();
    await Future<void>.delayed(Duration.zero);
    return seen;
  }

  for (final (label, networks, expected) in <(String, List<String>, bool)>[
    ('Wi-Fi', ['wifi'], true),
    ('Wi-Fi with a VPN', ['wifi', 'vpn'], true),
    ('mobile data', ['mobile'], false),
    ('ethernet', ['ethernet'], false),
    ('no connection', ['none'], false),
  ]) {
    test('initial state: $label is ${expected ? '' : 'not '}Wi-Fi', () async {
      current = networks;
      final container = ProviderContainer.test();
      final seen = await observe(container, () async {});
      expect(seen, [expected]);
    });
  }

  test('follows connectivity changes', () async {
    final container = ProviderContainer.test();
    final seen = await observe(container, () async {
      sink!.success(['none']);
      await Future<void>.delayed(Duration.zero);
      sink!.success(['mobile']);
      await Future<void>.delayed(Duration.zero);
      sink!.success(['wifi']);
    });
    expect(seen.first, isTrue);
    expect(seen.last, isTrue);
    expect(seen, contains(false));
  });
}

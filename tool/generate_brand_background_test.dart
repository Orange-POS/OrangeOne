import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:orange_one/shared/theme/orange_theme.dart';

/// Run with flutter test tool/generate_brand_background_test.dart after
/// changing the shared gradient. Native artwork uses the same shader.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export shared gradient for native launch backgrounds', () async {
    const width = 1170;
    const height = 2532;
    final recording = ui.PictureRecorder();
    final canvas = ui.Canvas(recording);
    const bounds = ui.Rect.fromLTWH(0, 0, 1170, 2532);
    canvas.drawRect(
      bounds,
      ui.Paint()..shader = OrangeTheme.gradient.createShader(bounds),
    );
    final picture = recording.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Gradient export failed.');
    final bytes = data.buffer.asUint8List();
    for (final path in [
      'assets/branding/launch_gradient.png',
      'android/app/src/main/res/drawable-nodpi/brand_launch_background.png',
      'ios/Runner/Assets.xcassets/LaunchBackground.imageset/launch_gradient.png',
    ]) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    final color = OrangeTheme.dark.toARGB32().toRadixString(16).substring(2);
    final colors = File('android/app/src/main/res/values/brand_colors.xml');
    await colors.writeAsString(
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<resources><color name="brand_launch_solid">#$color</color></resources>\n',
    );
    image.dispose();
    picture.dispose();
  });
}

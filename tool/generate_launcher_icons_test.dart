import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Run with `flutter test tool/generate_launcher_icons_test.dart` after
/// updating `assets/branding/app_logo.png` (and `tool/sync_branding.ps1`).
///
/// Launcher icons show only the fruit (with its leaf) of the supplied logo,
/// never the wordmark. The fruit is cut from the original artwork above the
/// first fully transparent row that separates it from the wordmark; it is
/// scaled, never recolored or redrawn. Development and staging keep their
/// DEV/STG banner (Android) or corner flag (iOS) so flavors stay distinct.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export fruit-only launcher icons for Android and iOS', () async {
    final fruit = await _Fruit.load('assets/branding/app_logo.png');
    final font = FontLoader('LauncherInter')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();

    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    const flavors = {'main': null, 'development': 'DEV', 'staging': 'STG'};

    for (final MapEntry(key: flavor, value: banner) in flavors.entries) {
      final res = 'android/app/src/$flavor/res';
      for (final MapEntry(key: bucket, value: scale) in densities.entries) {
        await _write(
          '$res/drawable-$bucket/ic_launcher_foreground.png',
          _adaptiveForeground(fruit, 108 * scale, banner),
        );
        await _write(
          '$res/mipmap-$bucket/ic_launcher.png',
          _legacy(fruit, 48 * scale, banner, round: false),
        );
        await _write(
          '$res/mipmap-$bucket/ic_launcher_round.png',
          _legacy(fruit, 48 * scale, banner, round: true),
        );
      }
    }

    // Android 12+ system splash icon (shared by all flavors, no banner):
    // 240 dp with an icon background, masked to a 160 dp circle, so the fruit
    // stays inside a 74 dp radius and the wordmark never appears clipped.
    for (final MapEntry(key: bucket, value: scale) in densities.entries) {
      await _write(
        'android/app/src/main/res/drawable-$bucket/splash_icon.png',
        _canvas(240 * scale, (canvas) {
          fruit.draw(canvas, ui.Offset(120 * scale, 120 * scale), 74 * scale);
        }),
      );
    }

    // Icon Composer layer: 1024 pt canvas, Xcode renders every size and the
    // opaque App Store icon from it.
    for (final bundle in ['AppIcon', 'AppIcon-dev', 'AppIcon-stg']) {
      await _write(
        'ios/Runner/AppIcons/$bundle.icon/Assets/Fruit.png',
        _canvas(1024, (canvas) {
          fruit.draw(canvas, const ui.Offset(512, 512), 360);
        }),
      );
    }
    fruit.dispose();
  });
}

/// The fruit-only region of the supplied logo.
class _Fruit {
  new(this.image, this.source, this.reach);

  final ui.Image image;

  /// Bounding box of the fruit and leaf in source pixels.
  final ui.Rect source;

  /// Farthest visible fruit pixel from [source]'s center, in source pixels.
  final double reach;

  static Future<_Fruit> load(String path) async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final data = await image.toByteData();
    if (data == null) throw StateError('Logo decoding failed.');
    final width = image.width;
    bool visible(int x, int y) => data.getUint8((y * width + x) * 4 + 3) > 8;
    bool rowVisible(int y) =>
        Iterable<int>.generate(width).any((x) => visible(x, y));

    var top = 0;
    while (!rowVisible(top)) {
      top++;
    }
    var bottom = top;
    while (bottom < image.height && rowVisible(bottom)) {
      bottom++;
    }
    if (bottom >= image.height) {
      throw StateError('No gap between the fruit and the wordmark.');
    }
    var left = width;
    var right = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = 0; x < width; x++) {
        if (visible(x, y)) {
          left = math.min(left, x);
          right = math.max(right, x + 1);
        }
      }
    }
    final rect = ui.Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
    var reach = 0.0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (visible(x, y)) {
          final offset = ui.Offset(x + .5, y + .5) - rect.center;
          reach = math.max(reach, offset.distance);
        }
      }
    }
    return _Fruit(image, rect, reach);
  }

  /// Draws the fruit centered on [center] so no visible pixel lies farther
  /// than [radius] from it.
  void draw(ui.Canvas canvas, ui.Offset center, double radius) {
    final scale = radius / reach;
    canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromCenter(
        center: center,
        width: source.width * scale,
        height: source.height * scale,
      ),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  void dispose() => image.dispose();
}

const _bannerColor = ui.Color(0xFF13B9FD);

/// 108 dp adaptive foreground; launchers show at most the central 72 dp and
/// guarantee only a 66 dp circle, so the fruit stays inside a 31 dp radius.
ui.Image _adaptiveForeground(_Fruit fruit, double size, String? banner) =>
    _canvas(size, (canvas) {
      final dp = size / 108;
      if (banner == null) {
        fruit.draw(canvas, ui.Offset(54 * dp, 54 * dp), 31 * dp);
        return;
      }
      fruit.draw(canvas, ui.Offset(54 * dp, 48 * dp), 25 * dp);
      _banner(canvas, ui.Rect.fromLTRB(0, 75 * dp, size, 90 * dp), banner);
    });

/// API 24–25 launcher: white rounded square or circle with the fruit.
ui.Image _legacy(
  _Fruit fruit,
  double size,
  String? banner, {
  required bool round,
}) => _canvas(size, (canvas) {
  final inset = size * (round ? .02 : .085);
  final bounds = ui.Rect.fromLTRB(inset, inset, size - inset, size - inset);
  final shape = round
      ? (ui.Path()..addOval(bounds))
      : (ui.Path()..addRRect(
          ui.RRect.fromRectAndRadius(bounds, ui.Radius.circular(size * .1)),
        ));
  canvas
    ..drawShadow(shape, const ui.Color(0xFF000000), size * .02, false)
    ..drawPath(shape, ui.Paint()..color = const ui.Color(0xFFFFFFFF))
    ..save()
    ..clipPath(shape);
  if (banner == null) {
    fruit.draw(canvas, ui.Offset(size / 2, size / 2), size * .34);
  } else {
    fruit.draw(canvas, ui.Offset(size / 2, size * .44), size * .29);
    _banner(canvas, ui.Rect.fromLTRB(0, size * .76, size, size * .9), banner);
  }
  canvas.restore();
});

void _banner(ui.Canvas canvas, ui.Rect band, String label) {
  canvas.drawRect(band, ui.Paint()..color = _bannerColor);
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: ui.TextAlign.center,
            fontFamily: 'LauncherInter',
            fontSize: band.height * .72,
            fontWeight: ui.FontWeight.w700,
            height: 1,
          ),
        )
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
        ..addText(label);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: band.width));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(band.left, band.center.dy - paragraph.height / 2),
  );
  paragraph.dispose();
}

ui.Image _canvas(double size, void Function(ui.Canvas canvas) paint) {
  final pixels = size.round();
  final recording = ui.PictureRecorder();
  paint(ui.Canvas(recording));
  final picture = recording.endRecording();
  final image = picture.toImageSync(pixels, pixels);
  picture.dispose();
  return image;
}

Future<void> _write(String path, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('PNG export failed for $path.');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data.buffer.asUint8List());
}

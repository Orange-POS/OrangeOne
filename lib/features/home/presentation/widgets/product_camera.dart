import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:orange_one/l10n/camera_messages.dart';
import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/code_camera.dart';

const List<BarcodeFormat> supportedProductFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.itf14,
];

// Apple Vision reports UPC-A as EAN-13 and Codabar needs newer iOS versions.
// Do not silently rewrite barcode values; Odoo uses exact string matching.
const List<BarcodeFormat> androidProductFormats = [
  ...supportedProductFormats,
  BarcodeFormat.upcA,
  BarcodeFormat.codabar,
];

typedef ProductCameraBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
  ValueChanged<String> onStatus,
);

final productCameraBuilderProvider = Provider<ProductCameraBuilder>(
  (ref) =>
      (context, onCode, onStatus) => CodeCamera(
        onCode: onCode,
        onStatus: onStatus,
        formats: defaultTargetPlatform == TargetPlatform.android
            ? androidProductFormats
            : supportedProductFormats,
        instructions: context.l10n.productCameraInstructions,
        readyMessage: context.l10n.productCameraReady,
        messages: context.l10n.cameraMessages,
        singleScan: false,
      ),
  name: 'productCameraBuilderProvider',
);

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Texts shown by [CodeCamera]. The defaults are English; callers with
/// localized screens pass translated values.
class CodeCameraMessages {
  const new({
    this.permissionRequired = 'Camera permission is required to scan',
    this.unavailable = 'Camera unavailable',
    this.paused = 'Camera paused',
    this.busy = 'Camera unavailable. Close other camera apps and try again.',
    this.openFailed =
        'Unable to open the camera. Check camera access in Settings.',
    this.tryAgain = 'Camera unavailable. Try again.',
    this.restricted = 'Camera access is restricted on this device.',
    this.openSettings = 'Open Settings',
    this.allowRetry = 'Allow camera / Retry',
  });

  /// Status when the permission is missing.
  final String permissionRequired;

  /// Status when the camera cannot start.
  final String unavailable;

  /// Status while the app is in the background.
  final String paused;
  final String busy;
  final String openFailed;
  final String tryAgain;
  final String restricted;
  final String openSettings;
  final String allowRetry;
}

/// Platform camera lifecycle shared by login and product scanners.
class CodeCamera extends StatefulWidget {
  const new({
    required this.onCode,
    required this.onStatus,
    required this.formats,
    required this.instructions,
    required this.readyMessage,
    this.singleScan = true,
    this.messages = const CodeCameraMessages(),
    super.key,
  });
  final ValueChanged<String> onCode;
  final ValueChanged<String> onStatus;
  final List<BarcodeFormat> formats;
  final String instructions;
  final String readyMessage;
  final bool singleScan;
  final CodeCameraMessages messages;

  @override
  State<CodeCamera> createState() => _CodeCameraState();
}

class _CodeCameraState extends State<CodeCamera> with WidgetsBindingObserver {
  late final _controller = MobileScannerController(
    autoStart: false,
    formats: widget.formats,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  PermissionStatus? _permission;
  String? _cameraError;
  var _starting = false;
  var _accepted = false;
  var _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_start(request: true)),
    );
  }

  Future<void> _start({bool request = false}) async {
    if (_starting || _accepted || !mounted || !_foreground) return;
    _starting = true;
    try {
      final permission = request
          ? await Permission.camera.request()
          : await Permission.camera.status;
      if (!mounted) return;
      setState(() {
        _permission = permission;
        _cameraError = null;
      });
      if (!permission.isGranted) {
        widget.onStatus(widget.messages.permissionRequired);
        return;
      }
      // Allow the preview to attach before starting its controller.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _accepted || !_foreground) return;
      await _controller.start();
      if (mounted) widget.onStatus(widget.readyMessage);
    } on MobileScannerException {
      if (mounted) {
        setState(() => _cameraError = widget.messages.busy);
        widget.onStatus(widget.messages.unavailable);
      }
    } on Exception {
      if (mounted) {
        setState(() => _cameraError = widget.messages.openFailed);
        widget.onStatus(widget.messages.unavailable);
      }
    } finally {
      _starting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
      widget.onStatus(widget.messages.paused);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permission != null && !_permission!.isGranted ||
        _cameraError != null) {
      final blocked = _permission?.isPermanentlyDenied ?? false;
      final restricted = _permission?.isRestricted ?? false;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _cameraError ??
                    (restricted
                        ? widget.messages.restricted
                        : widget.instructions),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              if (!restricted)
                FilledButton(
                  onPressed: () {
                    if (blocked) {
                      unawaited(openAppSettings());
                    } else {
                      unawaited(_start(request: true));
                    }
                  },
                  child: Text(
                    blocked
                        ? widget.messages.openSettings
                        : widget.messages.allowRetry,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (_permission == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MobileScanner(
      controller: _controller,
      errorBuilder: (context, error) {
        if (_starting ||
            error.errorCode == MobileScannerErrorCode.controllerUninitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _starting || _cameraError != null) return;
          setState(() => _cameraError = widget.messages.tryAgain);
          widget.onStatus(widget.messages.unavailable);
        });
        return Center(
          child: Text(
            widget.messages.tryAgain,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
      onDetect: (capture) {
        if (_accepted || !_foreground) return;
        final code = capture.barcodes
            .where(
              (barcode) =>
                  barcode.rawValue != null &&
                  widget.formats.contains(barcode.format),
            )
            .firstOrNull
            ?.rawValue;
        if (code == null) return;
        _accepted = widget.singleScan;
        if (widget.singleScan) unawaited(_controller.stop());
        widget.onCode(code);
      },
    );
  }
}

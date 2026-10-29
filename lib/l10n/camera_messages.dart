import 'package:orange_one/l10n/l10n.dart';
import 'package:orange_one/shared/widgets/code_camera.dart';

/// Localized texts for [CodeCamera]'s permission and error states.
extension LocalizedCameraMessages on AppLocalizations {
  CodeCameraMessages get cameraMessages => CodeCameraMessages(
    permissionRequired: cameraPermissionRequired,
    unavailable: cameraUnavailable,
    paused: cameraPaused,
    busy: cameraBusy,
    openFailed: cameraOpenFailed,
    tryAgain: cameraTryAgain,
    restricted: cameraRestricted,
    openSettings: cameraOpenSettings,
    allowRetry: cameraAllowRetry,
  );
}

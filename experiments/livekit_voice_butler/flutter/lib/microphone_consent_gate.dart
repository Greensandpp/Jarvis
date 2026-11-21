/// Pure policy object: prevents accidental realtime microphone activation.
/// No LiveKit state, OS permissions or network access inside this class.
class MicrophoneConsentGate {
  bool _systemPermissionGranted = false;
  bool _userApproved = false;
  bool _streaming = false;

  bool get mayConnect =>
      _systemPermissionGranted && _userApproved;
  bool get streaming => _streaming;

  void updatePermission(bool granted) {
    _systemPermissionGranted = granted;
    if (!granted) _streaming = false;
  }

  void approveForSession() {
    _userApproved = true;
  }

  /// Approval must be given anew after disconnect or app backgrounding.
  void revoke() {
    _userApproved = false;
    _streaming = false;
  }

  bool requestMicrophoneEnable() {
    if (!mayConnect) return false;
    _streaming = true;
    return true;
  }

  void microphoneDisabled() {
    _streaming = false;
  }
}

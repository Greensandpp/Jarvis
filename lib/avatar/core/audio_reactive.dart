import 'math3d.dart';

/// Real-time audio amplitude hooks for avatar reaction.
///
/// Two inputs feed it:
///  * microphone level (JARVIS recogniser sound level, or Gemini Live level)
///  * output (speech) level — today derived from the viseme timeline because
///    platform TTS does not expose PCM; a PCM/visualizer tap can call
///    [pushOutput] directly later.
///
/// Each input goes through an attack/release envelope follower so the
/// renderer gets smooth, frame-rate independent values plus onset pulses.
class AudioReactiveBus {
  AudioReactiveBus({this.attack = 0.03, this.release = 0.18});

  final double attack; // half-life seconds when rising
  final double release; // half-life seconds when falling

  double _micTarget = 0, _outTarget = 0;
  double _mic = 0, _out = 0;
  double _micSlow = 0;
  double _onset = 0;
  int _onsets = 0;

  /// Raw microphone level in 0..1 (values outside are clamped).
  void pushMic(double level) => _micTarget = clamp01(level.isFinite ? level : 0);

  /// Raw output/speech level in 0..1.
  void pushOutput(double level) => _outTarget = clamp01(level.isFinite ? level : 0);

  double get mic => _mic;
  double get output => _out;

  /// Combined drive used by glow / lightning / particles.
  double get level => _mic > _out ? _mic : _out;

  /// Short decaying pulse (0..1) fired when the mic level jumps (syllables).
  double get onset => _onset;
  int get onsetCount => _onsets;

  void tick(double dt) {
    if (!(dt > 0)) return;
    double follow(double cur, double target) =>
        cur + (target - cur) * approach(dt, target > cur ? attack : release);
    _mic = follow(_mic, _micTarget);
    _out = follow(_out, _outTarget);
    _micSlow += (_mic - _micSlow) * approach(dt, 0.35);
    if (_mic - _micSlow > 0.18 && _onset < 0.35) {
      _onset = 1;
      _onsets++;
    }
    _onset *= 1 - approach(dt, 0.09);
  }

  void reset() {
    _micTarget = _outTarget = _mic = _out = _micSlow = _onset = 0;
  }
}

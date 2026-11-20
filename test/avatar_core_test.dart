import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:private_agent/avatar/avatar_runtime.dart';
import 'package:private_agent/avatar/core/audio_reactive.dart';
import 'package:private_agent/avatar/core/avatar_scene.dart';
import 'package:private_agent/avatar/core/avatar_settings.dart';
import 'package:private_agent/avatar/core/avatar_state_machine.dart';
import 'package:private_agent/avatar/core/math3d.dart';
import 'package:private_agent/avatar/core/render_list.dart';
import 'package:private_agent/avatar/core/rigs.dart';
import 'package:private_agent/avatar/core/viseme.dart';

void _run(AvatarStateMachine m, double seconds, {double step = 1 / 60}) {
  for (var t = 0.0; t < seconds; t += step) {
    m.tick(step);
  }
}

void main() {
  group('AvatarStateMachine', () {
    test('INTRO → MATERIALIZING → IDLE on the storyboard timeline', () {
      final m = AvatarStateMachine();
      expect(m.state, AvatarState.intro);
      expect(m.humanoidFormation, 0);
      _run(m, 1.45);
      expect(m.state, AvatarState.intro);
      expect(m.platformPower, greaterThan(0.9));
      _run(m, 0.1);
      expect(m.state, AvatarState.materializing);
      _run(m, 1.0);
      expect(m.humanoidFormation, inExclusiveRange(0.3, 0.99));
      expect(m.serpentFormation, 0);
      _run(m, 1.3);
      expect(m.humanoidFormation, 1);
      expect(m.serpentFormation, greaterThan(0.2));
      _run(m, 0.9);
      expect(m.activation, greaterThan(0.3), reason: 'power activation burst during reveal');
      _run(m, 1.4);
      expect(m.state, AvatarState.idle);
      expect(m.serpentFormation, 1);
      expect(m.history, [AvatarState.intro, AvatarState.materializing, AvatarState.idle]);
    });

    test('conversation requests during formation are queued, not cut in', () {
      final m = AvatarStateMachine();
      _run(m, 2);
      expect(m.request(AvatarState.listening), isTrue);
      expect(m.state, AvatarState.materializing);
      expect(m.pending, AvatarState.listening);
      _run(m, 4.5);
      expect(m.state, AvatarState.listening);
    });

    test('phase mapping covers every JARVIS phase', () {
      expect(AvatarStateMachine.stateForPhase('idle'), AvatarState.idle);
      expect(AvatarStateMachine.stateForPhase('listening'), AvatarState.listening);
      expect(AvatarStateMachine.stateForPhase('thinking'), AvatarState.thinking);
      expect(AvatarStateMachine.stateForPhase('executing'), AvatarState.thinking);
      expect(AvatarStateMachine.stateForPhase('speaking'), AvatarState.speaking);
      expect(AvatarStateMachine.stateForPhase('bogus'), AvatarState.idle);
    });

    test('LISTENING / THINKING / SPEAKING cross-fade and CLOSING dissolves', () {
      final m = AvatarStateMachine(skipIntro: true);
      final seen = <String>[];
      m.onTransition = (a, b) => seen.add('${a.name}>${b.name}');
      for (final s in ['listening', 'thinking', 'speaking', 'idle']) {
        m.applyPhaseName(s);
        _run(m, 0.1);
        final st = AvatarStateMachine.stateForPhase(s);
        expect(m.weight(st), inExclusiveRange(0.0, 1.0), reason: 'mid blend for $s');
        _run(m, 0.5);
        expect(m.weight(st), closeTo(1, 1e-9));
      }
      expect(seen, ['idle>listening', 'listening>thinking', 'thinking>speaking', 'speaking>idle']);
      expect(m.request(AvatarState.closing), isTrue);
      _run(m, AvatarTimeline.closing + 0.1);
      expect(m.closed, isTrue);
      expect(m.humanoidFormation, 0);
      expect(m.serpentFormation, 0);
      expect(m.request(AvatarState.listening), isFalse, reason: 'closed avatar ignores conversation');
      m.replayIntro();
      expect(m.state, AvatarState.intro);
      expect(m.closed, isFalse);
    });

    test('illegal transitions are refused and large dt is clamped', () {
      expect(AvatarStateMachine.canTransition(AvatarState.closing, AvatarState.idle), isFalse);
      expect(AvatarStateMachine.canTransition(AvatarState.intro, AvatarState.speaking), isFalse);
      final m = AvatarStateMachine();
      m.tick(10); // app resumed after a long pause
      expect(m.state, AvatarState.intro, reason: 'a stall must not skip the intro');
      m.tick(double.nan);
      m.tick(-1);
      expect(m.clock, closeTo(0.25, 1e-9));
    });
  });

  group('AvatarSettings', () {
    test('JSON round trip and per-avatar key', () {
      const s = AvatarSettings(primaryColor: 0xFF112233, particleDensity: 0.4, scale: 1.2, offsetX: -0.1,
          speed: 1.5, glow: 0.8, lightning: 0.2, introSound: false, backgroundEffects: false,
          performance: AvatarPerformanceMode.battery);
      final back = AvatarSettings.decode(s.encode());
      expect(back, s);
      expect(back.toJson()['primary'], '#112233');
      expect(AvatarSettings.storageKey('serpent_guardian'), 'avatar_settings_v1_serpent_guardian');
    });

    test('corrupted or out-of-range storage never crashes and is clamped', () {
      expect(AvatarSettings.decode('{not json'), AvatarSettings.defaults);
      expect(AvatarSettings.decode(null), AvatarSettings.defaults);
      final s = AvatarSettings.decode('{"scale": 9, "speed": -3, "glow": "x", "primary": "#zz", "performance": "turbo"}');
      expect(s.scale, 1.4);
      expect(s.speed, 0.25);
      expect(s.glow, AvatarSettings.defaults.glow);
      expect(s.primaryColor, AvatarSettings.defaults.primaryColor);
      expect(s.performance, AvatarSettings.defaults.performance);
      expect(const AvatarSettings().copyWith(offsetY: 5).offsetY, 0.3);
    });

    test('HEX / RGB parsing', () {
      expect(parseHex('#00E8A2'), 0xFF00E8A2);
      expect(parseHex('00e8a2'), 0xFF00E8A2);
      expect(parseHex('#0f0'), 0xFF00FF00);
      expect(parseHex('#8000E5FF'), 0x8000E5FF);
      expect(parseHex('rgb(255, 200, 87)'), 0xFFFFC857);
      expect(parseHex('rgb(300,0,0)'), isNull);
      expect(parseHex('#12345'), isNull);
      expect(parseHex('green'), isNull);
      expect(formatHex(0xFF00E5FF), '#00E5FF');
      expect(formatHex(0x8000E5FF), '#8000E5FF');
    });
  });

  group('Visemes (future Tamil lip sync interface)', () {
    test('Tamil script maps consonant + vowel sign, virama and inherent a', () {
      final tl = const TamilVisemeMapper().map('வணக்கம்');
      final seq = tl.events.map((e) => e.viseme).toList();
      // வ ண க் க ம் → ff aa(inherent) nn aa kk kk aa pp
      expect(seq.first, Viseme.ff);
      expect(seq, contains(Viseme.nn));
      expect(seq, contains(Viseme.kk));
      expect(seq.last, Viseme.pp, reason: 'ம் ends with closed lips');
      expect(tl.duration, inExclusiveRange(0.3, 1.5));
    });

    test('Tanglish digraphs and English map, punctuation pauses', () {
      final tl = const TamilVisemeMapper().map('Seri boss, naan paakren.');
      final seq = tl.events.map((e) => e.viseme).toSet();
      expect(seq, containsAll([Viseme.ss, Viseme.pp, Viseme.aa, Viseme.nn, Viseme.kk, Viseme.sil]));
      expect(tl.events.last.viseme, isNot(Viseme.sil), reason: 'trailing silence trimmed');
      final fast = const TamilVisemeMapper(rate: 2).map('Seri boss, naan paakren.');
      expect(fast.duration, closeTo(tl.duration / 2, 0.01));
    });

    test('timeline sampling is normalised, blends at boundaries and drives the jaw', () {
      final tl = const TamilVisemeMapper().map('aama ma');
      for (var t = 0.0; t < tl.duration; t += 0.007) {
        final w = tl.sample(t);
        final sum = w.values.fold(0.0, (a, b) => a + b);
        expect(sum, closeTo(1, 1e-6), reason: 'weights sum to 1 at t=$t');
      }
      expect(tl.sample(-1), {Viseme.sil: 1});
      expect(tl.sample(tl.duration + 1), {Viseme.sil: 1});
      expect(tl.jawOpen(0.05), greaterThan(0.5), reason: '"aa" opens the jaw');
      final face = ProceduralFaceRig()
        ..setVisemeWeights({Viseme.ou: 1})
        ..setJawOpen(2)
        ..setGaze(5, -5);
      expect(face.round, 1);
      expect(face.jawOpen, 1);
      expect(face.gazeX, 1);
      expect(face.gazeY, -1);
    });

    test('empty / emoji-only text produces no mouth motion', () {
      expect(const TamilVisemeMapper().map('').duration, 0);
      expect(const TamilVisemeMapper().map('🐍🐍 ...').duration, 0);
    });
  });

  group('Audio reaction hooks', () {
    test('envelope follower rises fast, decays slower, fires onsets', () {
      final bus = AudioReactiveBus();
      bus.pushMic(1);
      for (var i = 0; i < 6; i++) {
        bus.tick(1 / 60);
      }
      expect(bus.mic, greaterThan(0.6));
      expect(bus.onsetCount, greaterThan(0));
      bus.pushMic(0);
      for (var i = 0; i < 6; i++) {
        bus.tick(1 / 60);
      }
      expect(bus.mic, greaterThan(0.2), reason: 'release is slower than attack');
      bus.pushOutput(double.nan);
      bus.tick(1 / 60);
      expect(bus.output.isFinite, isTrue);
    });
  });

  group('Procedural rigs', () {
    test('serpent spine is continuous, finite and wraps the humanoid', () {
      final rig = SerpentRig(segments: 64);
      for (var f = 0; f < 600; f++) {
        rig.update(RigDrive(time: f / 60, idle: 1), Vec3.zero, 1 / 60);
        expect(rig.spine.length, 64);
        for (var i = 1; i < rig.spine.length; i++) {
          final step = (rig.spine[i].position - rig.spine[i - 1].position).length;
          expect(step, lessThan(0.25), reason: 'no tearing at frame $f seg $i');
          expect(rig.spine[i].normal.isFinite && rig.spine[i].binormal.isFinite, isTrue);
          expect(rig.spine[i].tangent.dot(rig.spine[i].normal).abs(), lessThan(1e-6));
        }
      }
      // Tail low near the platform, head high on the upper right.
      expect(rig.spine.first.position.y, lessThan(-0.7));
      expect(rig.head.position.y, greaterThan(0.75));
      expect(rig.head.position.x, greaterThan(0.4));
    });

    test('serpent head and jaw move independently of the body', () {
      final rig = SerpentRig();
      final yaws = <double>{};
      var maxJaw = 0.0;
      for (var f = 0; f < 60 * 14; f++) {
        rig.update(RigDrive(time: f / 60, idle: 1), Vec3.zero, 1 / 60);
        yaws.add((rig.head.forward.x * 100).roundToDouble());
        if (rig.head.jaw > maxJaw) maxJaw = rig.head.jaw;
      }
      expect(yaws.length, greaterThan(10), reason: 'head turns');
      expect(maxJaw, greaterThan(0.3), reason: 'occasional controlled jaw opening');
      rig.update(const RigDrive(time: 20, idle: 0, activation: 1), Vec3.zero, 1);
      expect(rig.head.jaw, greaterThan(0.6), reason: 'jaw opens wide at power reveal');
    });

    test('humanoid breathes, hovers and raises arms on activation', () {
      final h = HumanoidRig();
      final ys = <double>[];
      for (var f = 0; f < 240; f++) {
        h.update(RigDrive(time: f / 60), 1 / 60);
        ys.add(h.root.y);
      }
      final span = ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
      expect(span, greaterThan(0.02), reason: 'floating hover');
      final idleHand = h.handL.y;
      h.update(const RigDrive(time: 5, activation: 1), 1 / 60);
      expect(h.handL.y, greaterThan(idleHand + 0.1));
      expect(h.bones.where((b) => b.name.startsWith('finger')).length, 6);
    });
  });

  group('AvatarScene draw list', () {
    RenderList frame(AvatarScene s, double seconds, {String phase = 'idle', double mic = 0}) {
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        s.update(1 / 60, phase: phase, micLevel: mic);
      }
      return s.build(412, 760);
    }

    test('intro shows only platform/particles; formed avatar has meshes', () {
      final s = AvatarScene();
      final intro = frame(s, 0.8);
      expect(intro.ops.whereType<TriOp>(), isEmpty, reason: 'no body before materialising');
      expect(intro.ops.whereType<LineOp>(), isNotEmpty);
      final formed = frame(s, 6.5);
      expect(s.machine.state, AvatarState.idle);
      final tris = formed.ops.whereType<TriOp>().toList();
      expect(tris.where((t) => !t.additive), isNotEmpty, reason: 'opaque metallic humanoid');
      expect(tris.where((t) => t.additive), isNotEmpty, reason: 'holographic serpent');
      expect(formed.triangleCount, greaterThan(1500));
      for (final t in tris) {
        expect(t.indices.every((i) => i * 2 + 1 < t.positions.length), isTrue);
        expect(t.positions.every((v) => v.isFinite), isTrue);
      }
    });

    test('particle pool respects budget for every performance mode', () {
      for (final mode in AvatarPerformanceMode.values) {
        final s = AvatarScene(settings: AvatarSettings(performance: mode, particleDensity: 1));
        frame(s, 7);
        final budget = SceneBudget.of(mode);
        expect(s.particleCount, lessThanOrEqualTo(budget.maxParticles), reason: mode.name);
        expect(s.particleCount, greaterThan(10), reason: mode.name);
      }
      expect(SceneBudget.of(AvatarPerformanceMode.battery).targetFps, 30);
    });

    test('speech cue animates the mouth; mic level brightens lightning drive', () {
      final s = AvatarScene(skipIntro: true);
      frame(s, 0.5);
      s.speak('Vanakkam boss, ready-a irukken.');
      var maxJaw = 0.0;
      for (var i = 0; i < 90; i++) {
        s.update(1 / 60, phase: 'speaking');
        if (s.face.jawOpen > maxJaw) maxJaw = s.face.jawOpen;
      }
      expect(maxJaw, greaterThan(0.35));
      expect(s.audio.output, greaterThan(0.05), reason: 'speech envelope hook');
      frame(s, 1, phase: 'listening', mic: 0.9);
      expect(s.audio.mic, greaterThan(0.5));
      expect(s.drive.listening, closeTo(1, 1e-6));
    });

    test('settings change live: colours, scale, background, lightning off', () {
      final s = AvatarScene(skipIntro: true);
      frame(s, 1);
      final a = s.build(412, 760);
      s.applySettings(const AvatarSettings(scale: 0.6, backgroundEffects: false, lightning: 0, primaryColor: 0xFFFF0000));
      frame(s, 2, phase: 'speaking');
      final b = s.build(412, 760);
      expect(b.background, isFalse);
      expect(b.backgroundTint, 0xFFFF0000);
      expect(s.boltCount, 0);
      double width(RenderList l) {
        final xs = <double>[];
        for (final t in l.ops.whereType<TriOp>().where((t) => !t.additive)) {
          for (final i in t.indices) {
            xs.add(t.positions[i * 2]);
          }
        }
        xs.sort();
        return xs.last - xs.first;
      }

      expect(width(b), lessThan(width(a) * 0.8), reason: 'avatar size slider');
    });
  });

  test('intro/outro sounds are valid PCM WAV files', () {
    for (final kind in ['intro', 'outro']) {
      final wav = AvatarSound.synthesize(kind);
      final bd = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(bd.getUint32(4, Endian.little), wav.length - 8);
      expect(bd.getUint32(24, Endian.little), 22050);
      expect(wav.length, greaterThan(22050));
    }
  });
}

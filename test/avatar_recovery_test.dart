import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_agent/avatar/avatar_engine.dart';
import 'package:private_agent/avatar/avatar_settings.dart';
import 'package:private_agent/avatar/avatar_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'all appearance and dock settings survive a new store; models stay independent',
    () async {
      final p = AvatarPreferences();
      await p.load();
      await p.select(AvatarModel.serpent);
      final s = p.current;
      s.primary = const Color(0xFFCC3377);
      s.speed = 1.4;
      s.audio = true;
      s.profile = GraphicsProfile.lite;
      s.x = .2;
      s.y = -.2;
      s.density = .3;
      s.lipSync = .4;
      p.dockHeight = 66;
      p.dockWidth = .8;
      p.dockBottom = 42;
      final expected = jsonEncode(s.toJson());
      await p.save();
      await p.select(AvatarModel.golden);
      p.current.speed = .7;
      await p.save();
      final r = AvatarPreferences();
      await r.load();
      expect(r.selected, AvatarModel.golden);
      expect(r.current.speed, .7);
      expect(jsonEncode(r.styleFor(AvatarModel.serpent).toJson()), expected);
      expect(r.dockHeight, 66);
      expect(r.dockBottom, 42);
    },
  );
  test('corrupted settings recover without deleting legacy data', () async {
    SharedPreferences.setMockInitialValues({
      AvatarPreferences.storageKey: '{bad',
      'jarvis_visual_mode_v1': 'mira',
    });
    final p = AvatarPreferences();
    await p.load();
    expect(p.selected, AvatarModel.originalOrb);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'jarvis_visual_mode_v1',
      ),
      'mira',
    );
    expect(
      AvatarStyle.fromJson({
        'scale': -100,
        'speed': double.nan,
      }, AvatarModel.serpent).scale,
      .4,
    );
    expect(parseHexColor('#FF0088'), const Color(0xFFFF0088));
    expect(parseHexColor('#bad-value'), isNull);
  });
  test('intro formation state, pause, closing and restart are bounded', () {
    final t = AvatarTimeline();
    t.request(AvatarState.listening);
    for (var i = 0; i < 25; i++) {
      t.tick(.1);
    }
    expect(t.state, AvatarState.listening);
    t.paused = true;
    final before = t.time;
    t.tick(600);
    expect(t.time, before);
    t.paused = false;
    t.close();
    for (var i = 0; i < 8; i++) {
      t.tick(.1);
    }
    expect(t.closed, isTrue);
    expect(t.progress, 0);
    t.restart();
    expect(t.closed, isFalse);
    expect(t.state, AvatarState.intro);
  });
  test(
    'Tamil audio interface uses provided timing; silence never invents lip movements',
    () {
      final f = AudioFaceDriver();
      expect(f.sample(dt: .1, speaking: true).jaw, 0);
      expect(f.sample(dt: .1, speaking: true, rms: .7).jaw, greaterThan(0));
      expect(f.sample(dt: .1, speaking: false, rms: .7).jaw, 0);
      final frame = f.sample(
        dt: .1,
        speaking: true,
        position: const Duration(milliseconds: 120),
        cues: [
          const VisemeCue(
            Duration(milliseconds: 100),
            Duration(milliseconds: 180),
            FaceFrame(jaw: .8, round: .4),
          ),
        ],
      );
      expect(frame.jaw, .8);
      expect(frame.round, .4);
    },
  );
  test('serpent spline stays finite and continuous across joints', () {
    for (final time in [0.0, 1.5, 50.0]) {
      final spline = SerpentSpline(time);
      var last = spline.at(0);
      for (var i = 1; i <= 1000; i++) {
        final p = spline.at(i / 1000);
        expect(p.length.isFinite, isTrue);
        expect((p - last).length, lessThan(.03));
        last = p;
      }
    }
  });
  testWidgets(
    'procedural renderer stops while backgrounded and safely resumes/disposes',
    (t) async {
      final key = GlobalKey<ProceduralAvatarViewState>();
      await t.pumpWidget(
        MaterialApp(
          home: ProceduralAvatarView(
            key: key,
            model: AvatarModel.serpent,
            style: AvatarStyle(),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      final active = key.currentState!;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final frames = active.paintedFrames;
      await t.pump(const Duration(seconds: 5));
      expect(active.paintedFrames, frames);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(active.paintedFrames, greaterThan(frames));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    },
  );
}

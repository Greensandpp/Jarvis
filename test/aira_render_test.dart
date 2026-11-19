import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/widgets/aira/aira_models.dart';
import 'package:private_agent/widgets/aira/aira_painter.dart';

/// Renders the real AIRA painter offscreen and measures the pixels. These are
/// measurements of actual rendering, not of reference screenshots.
Future<Uint8List> _render(AiraModel model, AiraVisualState state, double t,
    {int w = 360, int h = 640, double detail = 1}) async {
  final frame = AiraFrame()
    ..t = t
    ..clock = t
    ..state = state
    ..stateAge = .4
    ..detail = detail
    ..energy = state.params.energy
    ..spread = state.params.spread
    ..warmth = state.params.warmth;
  final painter = AiraCorePainter(model: model, frame: frame);
  final rec = ui.PictureRecorder();
  painter.paint(ui.Canvas(rec), ui.Size(w.toDouble(), h.toDouble()));
  expect(painter.lastPaintFailed, isFalse, reason: '${model.name} paint threw');
  final img = await rec.endRecording().toImage(w, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final out = bytes.buffer.asUint8List();
  final dir = Platform.environment['AIRA_RENDER_DIR'];
  if (dir != null) {
    final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    File('$dir/${model.name}_${state.name}_${(t * 10).round()}.png')
        .writeAsBytesSync(png.buffer.asUint8List());
  }
  return out;
}

({double mean, double bright, double peak}) _stats(Uint8List px) {
  var sum = 0.0, bright = 0, peak = 0.0;
  final n = px.length ~/ 4;
  for (var i = 0; i < n; i++) {
    final l = (.2126 * px[i * 4] + .7152 * px[i * 4 + 1] + .0722 * px[i * 4 + 2]) / 255;
    sum += l;
    if (l > .55) bright++;
    if (l > peak) peak = l;
  }
  return (mean: sum / n, bright: bright / n, peak: peak);
}

/// 24x24 RGB signature for structural comparison.
List<double> _sig(Uint8List px, int w, int h) {
  const g = 24;
  final out = List<double>.filled(g * g * 3, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final cell = ((y * g ~/ h) * g + (x * g ~/ w)) * 3;
      final i = (y * w + x) * 4;
      out[cell] += px[i];
      out[cell + 1] += px[i + 1];
      out[cell + 2] += px[i + 2];
    }
  }
  final per = (w / g) * (h / g) * 255;
  return [for (final v in out) v / per];
}

double _diff(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s / a.length;
}

void main() {
  test('all ten AIRA models are present with unique names', () {
    expect(AiraModel.values, hasLength(10));
    expect(AiraModel.values.map((m) => m.label).toSet(), {
      'Neural Reactor', 'Amber Hologram', 'Electric Web', 'AI Head', 'Jellyfish',
      'Violet Vortex', 'Aurora Ribbon', 'DNA Helix', 'Crystal Bloom', 'Solar Flare',
    });
    expect(AiraVisualState.values.map((s) => s.name), [
      'idle', 'listening', 'thinking', 'processing', 'completed', 'speaking',
    ]);
  });

  testWidgets('each model is bright, animated and structurally distinct', (tester) async {
    await tester.runAsync(() async {
      final sigs = <AiraModel, List<double>>{};
      final fails = <String>[], report = <String>[];
      for (final m in AiraModel.values) {
        final a = await _render(m, AiraVisualState.idle, 1.0);
        final b = await _render(m, AiraVisualState.idle, 2.7);
        final s = _stats(a);
        final motion = _diff(_sig(a, 360, 640), _sig(b, 360, 640));
        report.add('${m.name}: mean=${s.mean.toStringAsFixed(3)} '
            'bright=${(s.bright * 100).toStringAsFixed(2)}% peak=${s.peak.toStringAsFixed(2)} '
            'motion=${motion.toStringAsFixed(4)}');
        // OLED black base with bright light: visible energy, white-hot peak.
        if (s.peak < .92) fails.add('${m.name} lacks a white-hot core');
        if (s.mean < .03) fails.add('${m.name} too dim: ${s.mean}');
        if (s.bright < .006) fails.add('${m.name} too little bright area: ${s.bright}');
        // Animation: frames over time must actually differ.
        if (motion < .004) fails.add('${m.name} appears static ($motion)');
        sigs[m] = _sig(a, 360, 640);
      }
      // Pairwise structural difference: no two models may look alike.
      final models = AiraModel.values;
      var minDiff = 1.0;
      String? pair;
      for (var i = 0; i < models.length; i++) {
        for (var j = i + 1; j < models.length; j++) {
          final d = _diff(sigs[models[i]]!, sigs[models[j]]!);
          if (d < minDiff) {
            minDiff = d;
            pair = '${models[i].name}/${models[j].name}';
          }
        }
      }
      report.add('min pairwise difference $minDiff ($pair)');
      // ignore: avoid_print
      print(report.join('\n'));
      expect(fails, isEmpty);
      expect(minDiff, greaterThan(.02), reason: 'too similar: $pair ($minDiff)');
    });
  });

  testWidgets('all six states render differently for every model', (tester) async {
    await tester.runAsync(() async {
      for (final m in AiraModel.values) {
        final base = _sig(await _render(m, AiraVisualState.idle, 1.5, w: 180, h: 320), 180, 320);
        for (final s in AiraVisualState.values.skip(1)) {
          final sig = _sig(await _render(m, s, 1.5, w: 180, h: 320), 180, 320);
          expect(_diff(base, sig), greaterThan(.003),
              reason: '${m.name} ${s.name} is indistinguishable from idle');
        }
      }
    });
  });

  testWidgets('battery detail still renders without errors', (tester) async {
    await tester.runAsync(() async {
      for (final m in AiraModel.values) {
        final px = await _render(m, AiraVisualState.speaking, .8,
            w: 120, h: 200, detail: AiraQuality.battery.detail);
        expect(_stats(px).peak, greaterThan(.8));
      }
    });
  });
}

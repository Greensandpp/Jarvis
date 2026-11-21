import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/speech_output_controller.dart';

void main() {
  test(
    'optional sound owns one output without pretending the assistant is speaking',
    () async {
      final states = <bool>[];
      final gate = Completer<void>();
      final c = SpeechOutputController(
        stopDrivers: () async {},
        onSpeaking: states.add,
      );
      final sound = c.speak((ticket) async {
        await gate.future;
      }, speaking: false);
      await Future<void>.delayed(Duration.zero);
      expect(c.activeRequestId, isNotNull);
      expect(states, isEmpty);
      await c.stop();
      await sound;
      gate.complete();
      expect(states, isNot(contains(true)));
    },
  );
  test(
    'cancel during synthesis prevents delayed output and clears state',
    () async {
      final ready = Completer<void>();
      final events = <String>[];
      final controller = SpeechOutputController(
        stopDrivers: () async {
          events.add('stop');
        },
        onSpeaking: (v) => events.add('$v'),
      );
      final first = controller.speak((ticket) async {
        await ready.future;
        if (!ticket.cancelled) events.add('OLD AUDIO');
      });
      await Future<void>.delayed(Duration.zero);
      await controller.stop();
      ready.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(events, isNot(contains('OLD AUDIO')));
      expect(events.last, 'stop');
    },
  );
  test(
    'rapid requests leave exactly one valid ticket and stale completion cannot clear new speech',
    () async {
      final gates = List.generate(20, (_) => Completer<void>());
      final valid = <int>[];
      final states = <bool>[];
      final controller = SpeechOutputController(
        stopDrivers: () async {},
        onSpeaking: states.add,
      );
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(
          controller.speak((ticket) async {
            await gates[i].future;
            if (!ticket.cancelled) valid.add(ticket.id);
          }),
        );
      }
      await Future<void>.delayed(Duration.zero);
      for (final g in gates) {
        g.complete();
      }
      await Future.wait(futures);
      expect(valid, [20]);
      expect(states.last, false);
    },
  );
  test(
    'replacement stops old driver before new playback; external Live session owns audio',
    () async {
      final events = <String>[];
      final controller = SpeechOutputController(
        stopDrivers: () async {
          events.add('stop');
        },
        onSpeaking: (v) {},
      );
      await controller.speak((t) async {
        events.add('play1');
      });
      await controller.speak((t) async {
        events.add('play2');
      });
      expect(events, ['stop', 'play1', 'stop', 'play2']);
      controller.externalSession = true;
      await controller.speak((t) async {
        events.add('forbidden');
      });
      expect(events, isNot(contains('forbidden')));
    },
  );
}

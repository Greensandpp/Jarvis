import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../lib/session_lease.dart';

void main() {
  test('background/disconnect revokes pending ownership before SDK close', () async {
    final drain = Completer<void>();
    var stops = 0;
    final lease = SessionLease(duration: const Duration(minutes: 2), stop: () {
      stops++;
      return drain.future;
    });
    final pending = lease.close();
    expect(lease.isClosed, true);
    expect(identical(lease.close(), pending), true);
    expect(stops, 1);
    drain.complete();
    await pending;
  });

  testWidgets('hard timeout stops once even with subsequent disconnect', (tester) async {
    var stops = 0;
    final lease = SessionLease(duration: const Duration(seconds: 120), stop: () async { stops++; });
    await tester.pump(const Duration(seconds: 119));
    expect(lease.isClosed, false);
    await tester.pump(const Duration(seconds: 1));
    expect(lease.isClosed, true);
    await lease.close();
    expect(stops, 1);
  });
}

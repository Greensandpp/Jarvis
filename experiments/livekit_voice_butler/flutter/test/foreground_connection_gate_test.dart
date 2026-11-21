import 'package:flutter_test/flutter_test.dart';
import '../lib/foreground_connection_gate.dart';

void main() {
  test('foreground ticket is valid until invalidation', () {
    final gate = ForegroundConnectionGate();
    final ticket = gate.begin();
    expect(gate.isCurrent(ticket), true);
    gate.invalidate();
    expect(gate.isCurrent(ticket), false);
  });

  test('background invalidates outstanding connect ticket immediately', () {
    final gate = ForegroundConnectionGate();
    final ticket = gate.begin();
    gate.wentToBackground();
    expect(gate.isCurrent(ticket), false);
    expect(gate.begin(), isNull);
  });

  test('resume cannot authorize old connection', () {
    final gate = ForegroundConnectionGate();
    final ticket = gate.begin();
    gate.wentToBackground();
    gate.resumed();
    expect(gate.isCurrent(ticket), false);
    expect(gate.isCurrent(gate.begin()), true);
  });

  test('manual disconnect invalidates outstanding mic permission request', () {
    final gate = ForegroundConnectionGate();
    final ticket = gate.begin();
    gate.invalidate();
    expect(gate.isCurrent(ticket), false);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/widgets/jarvis_local_visuals.dart';

void main() {
  testWidgets('APEX uses local renderer with visible reactor label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: JarvisLocalVisual(apex: true))),
    ));
    expect(find.text('APEX • REACTOR'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MIRA uses different local renderer with no WebView', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: JarvisLocalVisual(apex: false))),
    ));
    expect(find.text('MIRA • NEURAL FIELD'), findsOneWidget);
    expect(find.textContaining('LOCAL VISUAL'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

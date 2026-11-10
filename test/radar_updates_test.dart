import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/wifi_direct_service.dart';
import 'package:sharem/src/core/update_service.dart';
import 'package:sharem/src/ui/nearby_radar.dart';
import 'package:sharem/src/ui/update_card.dart';

void main() {
  testWidgets('real Wi-Fi Direct peer on radar is clickable', (tester) async {
    WifiDirectPeer? selected;
    const peer = WifiDirectPeer(
      address: '02:11:22:33:44:55', name: 'Nearby Android', status: 3);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(
        width: 320, height: 320,
        child: NearbyRadar(
          deviceName: 'My phone', peers: const [],
          directPeers: const [peer],
          onTap: (_) {}, onDirectTap: (p) => selected = p,
        ),
      ))),
    ));
    final button = find.byKey(const Key('direct-peer-02:11:22:33:44:55'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(selected?.name, 'Nearby Android');
  });

  testWidgets('no published release is not displayed as raw 404', (tester) async {
    final update = UpdateService()
      ..currentVersion = '0.5.0'
      ..phase = UpdatePhase.unpublished;
    addTearDown(update.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: UpdateCard(updates: update),
      )),
    ));
    expect(find.textContaining('لم يُنشر إصدار تحديثات'), findsOneWidget);
    expect(find.textContaining('404'), findsNothing);
  });
}

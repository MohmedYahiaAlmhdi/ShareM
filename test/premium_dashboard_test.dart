import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharem/src/core/transfer_models.dart';
import 'package:sharem/src/ui/premium_dashboard.dart';
import 'package:sharem/src/ui/sharem_theme.dart';

void main() {
  testWidgets('primary actions are discoverable and connected', (tester) async {
    ShareCategory? chosen;
    var receives = 0;
    var pairing = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ShareMTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: PremiumDashboard(
          deviceName: 'جهازي',
          running: true,
          peers: <NearbyDevice>[],
          history: <TransferEntry>[],
          onSend: (category) => chosen = category,
          onReceive: () => receives++,
          onPair: () => pairing++,
          onHistory: () {},
          onSettings: () {},
          onRefresh: () {},
          onPeer: (_) {},
        )),
      ),
    ));
    expect(find.text('ShareM'), findsOneWidget);
    expect(find.byKey(const Key('main-send')), findsOneWidget);
    expect(find.byKey(const Key('main-receive')), findsOneWidget);
    await tester.tap(find.byKey(const Key('main-send')));
    expect(chosen, ShareCategory.all);
    await tester.tap(find.byKey(const Key('main-receive')));
    expect(receives, 1);
    await tester.ensureVisible(find.byKey(const Key('nearby-pair')));
    await tester.tap(find.byKey(const Key('nearby-pair')));
    expect(pairing, 1);
  });

  testWidgets('file category opens chosen media type', (tester) async {
    ShareCategory? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: PremiumDashboard(
          deviceName: 'Test',
          running: false,
          peers: <NearbyDevice>[],
          history: <TransferEntry>[],
          onSend: (category) => chosen = category,
          onReceive: () {},
          onPair: () {},
          onHistory: () {},
          onSettings: () {},
          onRefresh: () {},
          onPeer: (_) {},
        )),
      ),
    ));
    await tester.ensureVisible(find.byKey(const Key('category-images')));
    await tester.tap(find.byKey(const Key('category-images')));
    expect(chosen, ShareCategory.images);
  });
}

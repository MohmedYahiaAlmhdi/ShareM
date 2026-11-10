import 'package:flutter/material.dart';
import '../core/transfer_models.dart';
import '../core/wifi_direct_service.dart';
import 'nearby_radar.dart';
import 'sharem_theme.dart';

enum ShareCategory { all, images, videos, audio, documents, apk }

class PremiumDashboard extends StatelessWidget {
  const PremiumDashboard({super.key,
    required this.deviceName, required this.running,
    required this.peers, required this.history,
    required this.onSend, required this.onReceive, required this.onPair,
    required this.onHistory, required this.onSettings,
    required this.onRefresh, required this.onPeer,
    this.directPeers = const <WifiDirectPeer>[],
    this.directAvailable = false, this.directBusy = false,
    this.directConnected = false, this.onDirectPeer,
    this.error,
  });

  final String deviceName;
  final bool running;
  final List<NearbyDevice> peers;
  final List<TransferEntry> history;
  final ValueChanged<ShareCategory> onSend;
  final VoidCallback onReceive, onPair, onHistory, onSettings, onRefresh;
  final ValueChanged<NearbyDevice> onPeer;
  final List<WifiDirectPeer> directPeers;
  final bool directAvailable, directBusy, directConnected;
  final ValueChanged<WifiDirectPeer>? onDirectPeer;
  final String? error;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final large = constraints.maxWidth >= 760;
      return SingleChildScrollView(
        key: const Key('premium-dashboard'),
        padding: EdgeInsets.symmetric(
          horizontal: large ? 34 : 17, vertical: 20),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 22),
              _summary(context, large),
              const SizedBox(height: 26),
              _heading(context, 'شارك ملفاتك', 'اختر ما تريد إرساله'),
              const SizedBox(height: 13),
              _categories(large),
              const SizedBox(height: 26),
              _nearby(context, large),
              const SizedBox(height: 25),
              _activity(context),
              const SizedBox(height: 15),
            ],
          ),
        )),
      );
    },
  );

  Widget _header(BuildContext context) => Row(children: [
    Container(
      height: 50, width: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          colors: [Color(0xFF39CFC9), Color(0xFF74BDFA)],
        )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Image.asset('assets/branding/sharem.png', fit: BoxFit.cover)),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ShareM', style: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w900,
          color: ShareMTheme.ink, letterSpacing: -.5)),
        Text('ملفاتك تصل أسرع، بخطوات أقل',
          style: TextStyle(fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    )),
    IconButton.filledTonal(
      key: const Key('settings-shortcut'),
      onPressed: onSettings,
      tooltip: 'الإعدادات',
      icon: const Icon(Icons.settings_outlined),
    ),
  ]);

  Widget _summary(BuildContext context, bool large) {
    final sent = history.where((x) =>
      x.status == TransferStatus.completed &&
      x.direction == TransferDirection.outgoing).length;
    final received = history.where((x) =>
      x.status == TransferStatus.completed &&
      x.direction == TransferDirection.incoming).length;
    return Container(
      padding: EdgeInsets.all(large ? 28 : 19),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [Color(0xFF82E0D8), Color(0xFF9BD3F3),
            Color(0xFFD4EEF7)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x132E9BA5), blurRadius: 23,
            offset: Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.wifi_tethering_rounded,
              size: 19, color: Color(0xFF075D72)),
            const SizedBox(width: 7),
            const Expanded(child: Text('مشاركة محلية بين أجهزتك',
              style: TextStyle(fontWeight: FontWeight.w700,
                fontSize: 12, color: Color(0xFF075D72)))),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(190),
                borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8,
                  color: running ? const Color(0xFF22AC83)
                    : Colors.orange),
                const SizedBox(width: 5),
                Text(running ? 'جاهز' : 'يتصل',
                  style: const TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Text('مرحبًا، ' + deviceName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: large ? 26 : 22,
              color: ShareMTheme.ink,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('أرسل الصور والفيديوهات والملفات بسهولة.',
            style: TextStyle(fontSize: 12,
              color: Color(0xFF285F6F))),
          const SizedBox(height: 18),
          Row(children: [
            _counter(Icons.north_east_rounded, 'مرسلة', sent),
            const SizedBox(width: 10),
            _counter(Icons.south_west_rounded, 'مستلمة', received),
            const SizedBox(width: 10),
            _counter(Icons.devices_rounded, 'أجهزة', peers.length + directPeers.length),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: const Key('main-send'),
              onPressed: () => onSend(ShareCategory.all),
              style: FilledButton.styleFrom(
                backgroundColor: ShareMTheme.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 54)),
              icon: const Icon(Icons.arrow_upward_rounded),
              label: const Text('إرسال'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              key: const Key('main-receive'),
              onPressed: onReceive,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: ShareMTheme.teal,
                minimumSize: const Size(0, 54)),
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const Text('استقبال'),
            )),
          ]),
        ],
      ),
    );
  }

  Widget _counter(IconData icon, String title, int count) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(130),
        borderRadius: BorderRadius.circular(17)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: ShareMTheme.teal),
          const SizedBox(width: 4),
          Text('$count', style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900,
            color: ShareMTheme.ink)),
        ]),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(
          fontSize: 10.5, color: Color(0xFF47727B))),
      ]),
    ));

  Widget _heading(BuildContext context, String title, String subtitle) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);

  Widget _categories(bool large) {
    const entries = [
      (ShareCategory.images, 'الصور', Icons.image_outlined,
        Color(0xFFE0F9F3), Color(0xFF098B81)),
      (ShareCategory.videos, 'الفيديو', Icons.play_circle_outline_rounded,
        Color(0xFFE1F3FF), Color(0xFF258CCB)),
      (ShareCategory.audio, 'الصوتيات', Icons.headphones_rounded,
        Color(0xFFFFF3E2), Color(0xFFC48B32)),
      (ShareCategory.documents, 'المستندات', Icons.description_outlined,
        Color(0xFFEDF0FF), Color(0xFF687BB9)),
      (ShareCategory.apk, 'ملفات APK', Icons.android_rounded,
        Color(0xFFE6F7E6), Color(0xFF40965A)),
      (ShareCategory.all, 'كل الملفات', Icons.folder_open_rounded,
        Color(0xFFE9F4F5), Color(0xFF347C85)),
    ];
    return LayoutBuilder(builder: (context, size) =>
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: entries.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: size.maxWidth > 660 ? 3 : 2,
          mainAxisSpacing: 11, crossAxisSpacing: 11,
          mainAxisExtent: large ? 124 : 111),
        itemBuilder: (context, index) {
          final item = entries[index];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(21),
            child: InkWell(
              key: Key('category-' + item.$1.name),
              onTap: () => onSend(item.$1),
              borderRadius: BorderRadius.circular(21),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: const Color(0xFFEAF2F3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(height: 45, width: 45,
                      decoration: BoxDecoration(
                        color: item.$4,
                        borderRadius: BorderRadius.circular(16)),
                      child: Icon(item.$3, color: item.$5)),
                    const SizedBox(height: 9),
                    Text(item.$2, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          );
        },
      ));
  }

  Widget _nearby(BuildContext context, bool large) {
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _heading(context, 'الأجهزة القريبة',
          'اختر جهازًا لإرسال الملفات إليه'),
        const SizedBox(height: 12),
        Text(peers.isEmpty && directPeers.isEmpty
          ? 'لم يظهر جهاز بعد. شغّل Wi-Fi على الهاتفين، افتح ShareM على كليهما، واضغط بحث.'
          : 'عُثر على ' + (peers.length + directPeers.length).toString() + ' جهاز قريب.',
          style: const TextStyle(color: Color(0xFF56727A),
            fontSize: 12.5, height: 1.6)),
        if (directBusy) const Padding(
          padding: EdgeInsets.only(top: 12),
          child: LinearProgressIndicator(minHeight: 3)),
        if (directConnected) const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('تم إنشاء اتصال Wi-Fi Direct. انتظر لحظة حتى يظهر الجهاز للملفات.',
            style: TextStyle(color: ShareMTheme.teal, fontSize: 12))),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('nearby-pair'),
          onPressed: onPair,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('إظهار QR أو مسحه')),
        const SizedBox(height: 7),
        TextButton.icon(
          onPressed: directBusy ? null : onRefresh,
          icon: const Icon(Icons.radar_rounded),
          label: Text(directBusy ? 'جارٍ اكتشاف الأجهزة…' : 'بحث عن أجهزة قريبة')),
        if (!directAvailable)
          const Padding(padding: EdgeInsets.only(top: 5),
            child: Text('اكتشاف Wi-Fi Direct يتطلب Android وجهازًا يدعم الميزة. يمكن استخدام QR على شبكة Wi-Fi مشتركة.',
              style: TextStyle(fontSize: 11, color: Colors.grey))),
        const SizedBox(height: 10),
        for (final peer in peers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phone_android_rounded, color: ShareMTheme.teal),
            title: Text(peer.name, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            subtitle: const Text('على الشبكة المحلية'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => onPeer(peer),
          ),
        for (final peer in directPeers)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wifi_tethering_rounded,
              color: Color(0xFF2794C4)),
            title: Text(peer.name, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            subtitle: const Text('Wi-Fi Direct • بدون راوتر'),
            trailing: const Icon(Icons.link_rounded),
            onTap: directBusy || directConnected || onDirectPeer == null ? null :
              () => onDirectPeer!(peer),
          ),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error!, style: const TextStyle(
            color: Colors.deepOrange, fontSize: 12))),
      ],
    );
    return Container(
      padding: EdgeInsets.all(large ? 21 : 16),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6F1F2))),
      child: large ? Row(children: [
        Expanded(flex: 6, child: NearbyRadar(
          peers: peers, deviceName: deviceName, onTap: onPeer,
          directPeers: directPeers, onDirectTap: directBusy || directConnected ? null : onDirectPeer,
          busy: directBusy)),
        const SizedBox(width: 18),
        Expanded(flex: 5, child: controls),
      ]) : Column(children: [
        NearbyRadar(peers: peers, deviceName: deviceName, onTap: onPeer,
          directPeers: directPeers,
          onDirectTap: directBusy || directConnected ? null : onDirectPeer,
          busy: directBusy),
        const SizedBox(height: 10),
        controls,
      ]),
    );
  }

  Widget _activity(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('النشاط الأخير',
          style: Theme.of(context).textTheme.titleLarge)),
        TextButton(onPressed: onHistory, child: const Text('عرض الكل')),
      ]),
      const SizedBox(height: 8),
      if (history.isEmpty)
        Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(20)),
          child: const Row(children: [
            Icon(Icons.history_rounded, color: ShareMTheme.teal),
            SizedBox(width: 11),
            Expanded(child: Text('ستظهر هنا آخر الملفات المرسلة والمستلمة.',
              style: TextStyle(fontSize: 12))),
          ]))
      else
        for (final entry in history.take(3))
          Card(child: ListTile(
            onTap: onHistory,
            leading: Icon(entry.direction == TransferDirection.outgoing
              ? Icons.north_east_rounded : Icons.south_west_rounded,
              color: ShareMTheme.teal),
            title: Text(entry.peerName, maxLines: 1,
              overflow: TextOverflow.ellipsis),
            subtitle: Text(entry.files.length.toString() +
              ' ملف • ' + humanSize(entry.totalBytes)),
            trailing: Icon(
              entry.status == TransferStatus.completed
                ? Icons.check_circle_rounded
                : Icons.pending_rounded,
              color: entry.status == TransferStatus.completed
                ? const Color(0xFF31B691) : Colors.amber),
          )),
    ],
  );
}

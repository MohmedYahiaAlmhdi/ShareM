import 'dart:async';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/lan_transfer_service.dart';
import '../core/transfer_models.dart';
import '../core/wifi_direct_service.dart';
import '../core/update_service.dart';
import 'update_card.dart';
import 'pairing_page.dart';
import 'sharem_theme.dart';
import 'premium_dashboard.dart';

class ShareMHomePage extends StatefulWidget {
  const ShareMHomePage({super.key, required this.service});
  final LanTransferService service;

  @override
  State<ShareMHomePage> createState() => _ShareMHomePageState();
}

class _ShareMHomePageState extends State<ShareMHomePage> {
  int _page = 0;
  String? _shownOffer;
  final WifiDirectService wifiDirect = WifiDirectService();
  final UpdateService updates = UpdateService();
  String? _connectedDirectIp;
  List<PlatformFile> _selectedFiles = [];
  bool _showingDevicePicker = false;
  bool _autoShowReceiveQr = false;
  int _lastAutoPickerPeerCount = 0;

  LanTransferService get service => widget.service;

  @override
  void initState() {
    super.initState();
    service.addListener(_onChange);
    wifiDirect.addListener(_onDirectChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeNetworking());
      unawaited(updates.check());
    });
  }

  @override
  void dispose() {
    service.removeListener(_onChange);
    wifiDirect.removeListener(_onDirectChange);
    wifiDirect.dispose();
    updates.dispose();
    super.dispose();
  }


  Future<void> _initializeNetworking() async {
    try {
      await service.start();
      await wifiDirect.initialize();
      if (mounted && wifiDirect.canScan) {
        await wifiDirect.discover();
      }
    } catch (e) {
      if (mounted) _message('تعذر بدء البحث عن الأجهزة: ' + e.toString());
    }
  }

  Future<void> _searchNearby() async {
    service.refresh();
    if (wifiDirect.canScan && !wifiDirect.busy) {
      await wifiDirect.discover();
    }
    if (wifiDirect.error != null && mounted) {
      _message('البحث: ' + wifiDirect.error!);
    }
  }

  Future<void> _connectDirectPeer(WifiDirectPeer peer) async {
    if (wifiDirect.busy || wifiDirect.connected) return;
    await wifiDirect.connect(peer.address);
    if (!mounted) return;
    if (wifiDirect.error != null) {
      _message('تعذّر اتصال Wi-Fi Direct: ' + wifiDirect.error!);
    } else {
      _message('جارٍ الاتصال بـ ' + peer.name +
        '… وافق على الاتصال من الجهاز الآخر عند الطلب.');
    }
  }

  void _openPairing({bool receive = false}) {
    setState(() {
      _autoShowReceiveQr = receive;
      _page = 3;
    });
    unawaited(_searchNearby());
  }

  void _onDirectChange() {
    if (!mounted) return;
    setState(() {});
    final ip = wifiDirect.ownerIp;
    if (!wifiDirect.connected) {
      _connectedDirectIp = null;
      return;
    }
    unawaited(service.refreshLocalAddress());
    if (wifiDirect.groupOwner || ip == null || ip.isEmpty ||
        _connectedDirectIp == ip) return;
    _connectedDirectIp = ip;
    unawaited(_connectGroupOwner(ip));
  }

  Future<void> _connectGroupOwner(String ip) async {
    // The native P2P negotiation happens before reaching the owner's TCP port.
    for (var attempt = 0; attempt < 8 && mounted; attempt++) {
      if (!wifiDirect.connected) return;
      try {
        if (service.running) {
          await service.addManualPeer(
            ip + ':' + LanTransferService.transferPort.toString(),
          );
          await service.introduceToGroupOwner(ip);
          if (mounted) {
            _message('اتصل ShareM بالمضيف عبر Wi-Fi Direct. اختر الملفات للإرسال.');
          }
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted && wifiDirect.connected) {
      _message('تكوّنت مجموعة Wi-Fi Direct لكن تعذر الوصول إلى ShareM على '
        'المضيف. تأكد من تشغيل ShareM على كلا الجهازين.');
    }
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_selectedFiles.isNotEmpty &&
        service.peers.length > _lastAutoPickerPeerCount &&
        _page == 3 && !_showingDevicePicker) {
      _lastAutoPickerPeerCount = service.peers.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showingDevicePicker) _chooseDevice();
      });
    }
    final offer = service.incomingOffer;
    if (offer != null && offer.status == 'pending' &&
        _shownOffer != offer.id) {
      _shownOffer = offer.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _offerDialog(offer);
      });
    }
  }

  Future<void> _offerDialog(IncomingOffer offer) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.move_to_inbox_rounded, size: 45,
            color: ShareMTheme.teal),
          title: const Text('طلب استقبال ملفات', textAlign: TextAlign.center),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('يريد الجهاز «' + offer.peerName + '» إرسال ملفات إليك.',
                textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Text('عدد الملفات: ' + offer.files.length.toString() +
                ' • ' + humanSize(offer.totalBytes)),
              const SizedBox(height: 12),
              SizedBox(height: 118,
                child: ListView(children: offer.files.map(
                  (f) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('• ' + f.name + ' (' + humanSize(f.size) + ')',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  )).toList())),
              const Text('اقبل فقط الملفات من جهاز تعرفه.',
                style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
            ]),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () {
                service.respondToOffer(false);
                Navigator.pop(dialogContext);
              },
              child: const Text('رفض'),
            ),
            FilledButton.icon(
              onPressed: () {
                service.respondToOffer(true);
                Navigator.pop(dialogContext);
                setState(() => _page = 1);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('قبول الملفات'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: service.deviceName);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل اسم الجهاز'),
        content: TextField(
          controller: controller, autofocus: true,
          maxLength: 36,
          decoration: const InputDecoration(hintText: 'اسم الجهاز'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('حفظ')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await service.rename(value);
      if (mounted) _message('تم تحديث اسم الجهاز');
    } catch (e) {
      if (mounted) _message(e.toString());
    }
  }

  Future<void> _pickCategory(ShareCategory category) async {
    try {
      final type = switch (category) {
        ShareCategory.images => FileType.image,
        ShareCategory.videos => FileType.video,
        ShareCategory.audio => FileType.audio,
        ShareCategory.documents => FileType.custom,
        ShareCategory.apk => FileType.custom,
        ShareCategory.all => FileType.any,
      };
      final extensions = switch (category) {
        ShareCategory.documents => <String>[
          'pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt',
          'pptx', 'csv', 'zip', 'json', 'odt', 'rtf', 'epub'],
        ShareCategory.apk => <String>['apk'],
        _ => null,
      };
      final files = await FilePicker.pickFiles(
        type: type, allowedExtensions: extensions);
      if (files.isEmpty || !mounted) return;
      setState(() {
        _selectedFiles = files;
        _lastAutoPickerPeerCount = service.peers.length;
      });
      await _chooseDevice();
    } catch (e) {
      if (mounted) _message('تعذر اختيار الملفات: ' + e.toString());
    }
  }

  Future<void> _sendTo(NearbyDevice peer) async {
    try {
      final files = _selectedFiles.isNotEmpty
        ? List<PlatformFile>.of(_selectedFiles)
        : await FilePicker.pickFiles();
      if (files.isEmpty || !mounted) return;
      setState(() {
        _selectedFiles = [];
        _page = 1;
      });
      _message('جارٍ تجهيز الملفات للإرسال إلى ' + peer.name);
      unawaited(service.sendFiles(peer, files));
    } catch (e) {
      if (mounted) _message('تعذر اختيار الملفات: ' + e.toString());
    }
  }

  Future<void> _chooseDevice() async {
    if (_showingDevicePicker || !mounted) return;
    _showingDevicePicker = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 25),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_selectedFiles.isNotEmpty
                  ? 'اختر جهازًا لإرسال ' +
                    _selectedFiles.length.toString() + ' ملف'
                  : 'اختر الجهاز المستقبِل',
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              if (service.peers.isEmpty && wifiDirect.peers.isEmpty) ...[
                const Icon(Icons.wifi_tethering_rounded,
                  size: 55, color: ShareMTheme.teal),
                const SizedBox(height: 11),
                const Text('لا توجد أجهزة متصلة بعد',
                  style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                const Text('امسح رمز QR أو استخدم Wi-Fi Direct، ثم اختر الجهاز.',
                  textAlign: TextAlign.center),
              ] else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final peer in service.peers)
                        Card(child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.phone_android_rounded)),
                          title: Text(peer.name),
                          subtitle: const Text('متاح على الشبكة المحلية'),
                          trailing: const Icon(Icons.arrow_back_ios_new_rounded),
                          onTap: () {
                            Navigator.pop(ctx);
                            _sendTo(peer);
                          },
                        )),
                    ],
                  ),
                ),
              for (final peer in wifiDirect.peers)
                Card(child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.wifi_tethering_rounded)),
                  title: Text(peer.name),
                  subtitle: const Text('Wi-Fi Direct • بدون راوتر'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_connectDirectPeer(peer));
                  },
                )),
              const SizedBox(height: 11),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openPairing();
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('QR أو Wi-Fi Direct')),
              if (_selectedFiles.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _selectedFiles = []);
                    Navigator.pop(ctx);
                  },
                  child: const Text('إلغاء اختيار الملفات')),
            ]),
          ),
        ),
      );
    } finally {
      _showingDevicePicker = false;
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 870;
    return Scaffold(
      body: SafeArea(child: Row(children: [
        if (wide) _sideNavigation(),
        Expanded(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: KeyedSubtree(
              key: ValueKey(_page),
              child: _page == 0 ? _dashboard(wide)
                  : _page == 1 ? _historyPage()
                  : _page == 2 ? _settingsPage()
                  : PairingPage(service: service, wifiDirect: wifiDirect,
                      autoShowQr: _autoShowReceiveQr),
            ),
          ),
        ))),
      ])),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() {
          _page = value;
          _autoShowReceiveQr = false;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz_rounded), label: 'العمليات'),
          NavigationDestination(icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded), label: 'الأجهزة'),
        ],
      ),
    );
  }

  Widget _sideNavigation() => Container(
    width: 238,
    padding: const EdgeInsets.fromLTRB(18, 36, 18, 24),
    color: Theme.of(context).cardColor,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _logo(44),
        const SizedBox(width: 12),
        const Text('ShareM', style: TextStyle(
          fontSize: 27, fontWeight: FontWeight.w900,
          letterSpacing: -1, color: ShareMTheme.teal)),
      ]),
      const SizedBox(height: 58),
      _navItem(0, Icons.dashboard_rounded, 'الرئيسية'),
      _navItem(1, Icons.swap_horiz_rounded, 'التحويلات'),
      _navItem(2, Icons.settings_rounded, 'الإعدادات'),
      _navItem(3, Icons.qr_code_scanner_rounded, 'الاقتران'),
      const Spacer(),
      const Text('ShareM • Local first', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Colors.grey)),
    ]),
  );

  Widget _navItem(int index, IconData icon, String label) {
    final active = _page == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        selected: active,
        selectedTileColor: ShareMTheme.teal.withAlpha(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: active ? ShareMTheme.teal : null),
        title: Text(label, style: TextStyle(fontWeight:
          active ? FontWeight.w800 : FontWeight.w500)),
        onTap: () => setState(() => _page = index),
      ),
    );
  }

  Widget _logo(double size) => Container(
    height: size, width: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [ShareMTheme.teal, ShareMTheme.mint]),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: Image.asset('assets/branding/sharem.png', fit: BoxFit.cover)),
  );

  Widget _pageHeader(String heading, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(children: [
      _logo(45),
      const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(desc, style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12)),
        ])),
      IconButton(
        onPressed: () => unawaited(_searchNearby()),
        tooltip: 'تحديث البحث',
        icon: const Icon(Icons.refresh_rounded),
      ),
    ]),
  );

  Widget _dashboard(bool wide) => PremiumDashboard(
    deviceName: service.deviceName,
    running: service.running,
    peers: service.peers,
    history: service.history,
    error: service.startupError,
    onSend: _pickCategory,
    onReceive: () => _openPairing(receive: true),
    onPair: _openPairing,
    onHistory: () => setState(() => _page = 1),
    onSettings: () => setState(() => _page = 2),
    onRefresh: () => unawaited(_searchNearby()),
    onPeer: _sendTo,
    directPeers: wifiDirect.peers,
    directAvailable: wifiDirect.canScan,
    directBusy: wifiDirect.busy,
    directConnected: wifiDirect.connected,
    onDirectPeer: (peer) => unawaited(_connectDirectPeer(peer)),
  );

  Widget _notice(String message, IconData icon, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(19),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ])),
  );

  Future<void> _exportReceived(TransferEntry entry) async {
    if (Platform.isLinux) {
      _message('مشاركة الملفات غير مدعومة من نافذة المشاركة في Linux بعد.');
      return;
    }
    try {
      final accessible = <XFile>[];
      for (final filePath in entry.receivedPaths) {
        if (await File(filePath).exists()) accessible.add(XFile(filePath));
      }
      if (accessible.isEmpty) {
        _message('لم يتم العثور على الملفات. ربما نُقلت أو حُذفت.');
        return;
      }
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final origin = Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
      await SharePlus.instance.share(ShareParams(
        files: accessible,
        sharePositionOrigin: origin,
      ));
    } catch (error) {
      if (mounted) _message('تعذر تصدير الملفات: ' + error.toString());
    }
  }

  Widget _historyPage() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 27),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader('عمليات النقل', 'تابع الملفات المرسلة والمستقبلة'),
      if (service.history.isEmpty)
        _notice('ستظهر عملياتك هنا بعد أول عملية نقل',
          Icons.inventory_2_outlined, ShareMTheme.teal)
      else
        for (final entry in service.history) _transferTile(entry),
    ]),
  );

  Widget _transferTile(TransferEntry entry) {
    final sending = entry.direction == TransferDirection.outgoing;
    final status = switch (entry.status) {
      TransferStatus.preparing => 'تجهيز الملفات',
      TransferStatus.waiting => 'بانتظار قبول المستقبِل',
      TransferStatus.transferring => 'جارٍ النقل',
      TransferStatus.completed => 'اكتمل بنجاح',
      TransferStatus.rejected => 'رُفض الطلب',
      TransferStatus.failed => 'فشل النقل',
      TransferStatus.cancelled => 'تم الإلغاء',
    };
    final accent = entry.status == TransferStatus.completed
      ? const Color(0xFF17A874)
      : (entry.status == TransferStatus.failed ||
          entry.status == TransferStatus.rejected)
        ? Colors.deepOrange
        : ShareMTheme.teal;

    return Card(child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: accent.withAlpha(22),
            child: Icon(sending ? Icons.north_east_rounded
              : Icons.south_west_rounded, color: accent)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.peerName, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w800)),
              Text(entry.files.length.toString() + ' ملف • ' +
                humanSize(entry.totalBytes),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          )),
          Text(status, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
          if (entry.isRunning && sending)
            IconButton(tooltip: 'إلغاء', onPressed: () => service.cancel(entry),
              icon: const Icon(Icons.close_rounded)),
        ]),
        if (entry.isRunning || entry.status == TransferStatus.completed) ...[
          const SizedBox(height: 13),
          LinearProgressIndicator(
            value: entry.progress, minHeight: 6,
            borderRadius: BorderRadius.circular(9),
            color: accent,
            backgroundColor: accent.withAlpha(25),
          ),
          const SizedBox(height: 7),
          Align(alignment: Alignment.centerLeft,
            child: Text((entry.progress * 100).toStringAsFixed(0) + '%',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ],
        if (entry.error != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(entry.error!, style:
              const TextStyle(fontSize: 11, color: Colors.deepOrange))),
        if (!sending && entry.status == TransferStatus.completed &&
            entry.receivedPaths.isNotEmpty)
          Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _exportReceived(entry),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('تصدير الملفات المستلمة'),
            ),
          ),
      ]),
    ));
  }

  Widget _settingsPage() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 27),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader('الجهاز والاستقبال', 'معلومات وإعدادات ShareM'),
      UpdateCard(updates: updates),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _openPairing,
        icon: const Icon(Icons.qr_code_rounded),
        label: const Text('إظهار QR أو البحث بـ Wi-Fi Direct'),
      ),
      const SizedBox(height: 14),
      Card(child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          _infoRow(Icons.phone_android_rounded, 'اسم هذا الجهاز',
            service.deviceName, _rename),
          const Divider(height: 30),
          _infoRow(Icons.wifi_rounded, 'حالة الاستقبال',
            service.running ? 'جاهز للاتصال بالأجهزة القريبة'
              : 'جارٍ بدء الخدمة', null),
          const Divider(height: 30),
          _infoRow(Icons.folder_copy_outlined, 'حفظ الملفات الواردة',
            'مستندات التطبيق / ShareM / Received', null),
        ]),
      )),
      const SizedBox(height: 16),
      _notice('يجب أن يكون الجهازان على الشبكة المحلية نفسها أو متصلين '
        'بنقطة اتصال مشتركة. النقل في هذه النسخة غير مشفر؛ '
        'استخدم شبكة موثوقة فقط.', Icons.info_outline,
        ShareMTheme.teal),
      const SizedBox(height: 15),
      const SizedBox(height: 20),
      const Text('ShareM • إصدار تجريبي 0.5.0',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
  );

  Widget _infoRow(IconData icon, String title, String subtitle,
      VoidCallback? action) => Row(children: [
        CircleAvatar(
          backgroundColor: ShareMTheme.teal.withAlpha(20),
          child: Icon(icon, color: ShareMTheme.teal)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(subtitle, style: const TextStyle(
              fontSize: 12, color: Colors.grey)),
          ],
        )),
        if (action != null)
          IconButton(onPressed: action, icon: const Icon(Icons.edit_outlined)),
      ]);
}

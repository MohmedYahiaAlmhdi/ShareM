import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/lan_transfer_service.dart';
import '../core/transfer_models.dart';
import 'sharem_theme.dart';

class ShareMHomePage extends StatefulWidget {
  const ShareMHomePage({super.key, required this.service});
  final LanTransferService service;

  @override
  State<ShareMHomePage> createState() => _ShareMHomePageState();
}

class _ShareMHomePageState extends State<ShareMHomePage> {
  int _page = 0;
  String? _shownOffer;

  LanTransferService get service => widget.service;

  @override
  void initState() {
    super.initState();
    service.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => service.start());
  }

  @override
  void dispose() {
    service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
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

  Future<void> _manualConnect() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الاتصال بعنوان الجهاز'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل العنوان الظاهر في ShareM على الجهاز الآخر.'),
          const SizedBox(height: 16),
          Directionality(textDirection: TextDirection.ltr,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '192.168.1.12:54321',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
            )),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('اتصال')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    try {
      await service.addManualPeer(value);
      if (mounted) _message('تم العثور على الجهاز بنجاح');
    } catch (e) {
      if (mounted) _message('تعذر الاتصال: ' + e.toString());
    }
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

  Future<void> _sendTo(NearbyDevice peer) async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty || !mounted) return;
      setState(() => _page = 1);
      _message('جارٍ تجهيز الملفات لإرسالها إلى ' + peer.name);
      unawaited(service.sendFiles(peer, files));
    } catch (e) {
      if (mounted) _message('تعذر اختيار الملفات: ' + e.toString());
    }
  }

  Future<void> _chooseDevice() async {
    if (service.peers.isEmpty) {
      await _manualConnect();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اختر الجهاز المستقبِل',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final peer in service.peers)
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.devices_rounded)),
              title: Text(peer.name),
              subtitle: Text(peer.endpoint,
                textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                _sendTo(peer);
              },
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _manualConnect();
            },
            icon: const Icon(Icons.add_link),
            label: const Text('إضافة جهاز بعنوان IP'),
          ),
        ]),
      )),
    );
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
                  : _page == 1 ? _historyPage() : _settingsPage(),
            ),
          ),
        ))),
      ])),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_outlined),
            selectedIcon: Icon(Icons.swap_horiz_rounded), label: 'العمليات'),
          NavigationDestination(icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
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
    child: Icon(Icons.all_inclusive_rounded, color: Colors.white,
      size: size * .62),
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
        onPressed: service.refresh,
        tooltip: 'تحديث البحث',
        icon: const Icon(Icons.refresh_rounded),
      ),
    ]),
  );

  Widget _dashboard(bool wide) => SingleChildScrollView(
    padding: EdgeInsets.symmetric(horizontal: wide ? 38 : 19, vertical: 26),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader('مرحبًا بك في ShareM', 'انقل ملفاتك بسرعة، دون إنترنت أو حساب'),
      _hero(wide),
      const SizedBox(height: 26),
      Row(children: [
        Expanded(child: Text('الأجهزة القريبة',
          style: Theme.of(context).textTheme.titleLarge)),
        TextButton.icon(
          onPressed: _manualConnect,
          icon: const Icon(Icons.add_link_rounded),
          label: const Text('اتصال يدوي'),
        ),
      ]),
      const SizedBox(height: 12),
      if (service.startupError != null)
        _notice(service.startupError!, Icons.error_outline, Colors.deepOrange),
      if (service.peers.isEmpty)
        _emptyDevices()
      else
        LayoutBuilder(builder: (ctx, bounds) {
          final count = bounds.maxWidth > 720 ? 3 :
              bounds.maxWidth > 450 ? 2 : 1;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: service.peers.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisExtent: 154,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemBuilder: (ctx, i) => _peerCard(service.peers[i]),
          );
        }),
      const SizedBox(height: 25),
      _sectionTitle('آخر عمليات النقل', () => setState(() => _page = 1)),
      const SizedBox(height: 12),
      if (service.history.isEmpty)
        _notice('لا توجد عمليات سابقة حتى الآن', Icons.history_rounded,
          ShareMTheme.teal)
      else for (final entry in service.history.take(2)) _transferTile(entry),
      const SizedBox(height: 36),
    ]),
  );

  Widget _hero(bool wide) => Container(
    constraints: const BoxConstraints(minHeight: 235),
    padding: EdgeInsets.all(wide ? 32 : 24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topRight, end: Alignment.bottomLeft,
        colors: [Color(0xFF086C71), Color(0xFF12A99C), Color(0xFF35CEAF)],
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [BoxShadow(color: ShareMTheme.teal.withAlpha(42),
        blurRadius: 28, offset: const Offset(0, 13))],
    ),
    child: Stack(children: [
      Positioned(left: -25, top: -65,
        child: Container(width: 210, height: 210,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withAlpha(40),
              width: 28)))),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.wifi_tethering_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('مشاركة دون خوادم أو حساب',
            style: TextStyle(color: Colors.white70, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        const Text('شارك كل شيء.\nفي لحظات.',
          style: TextStyle(color: Colors.white, fontSize: 30,
            fontWeight: FontWeight.w900, height: 1.35)),
        const SizedBox(height: 23),
        Wrap(spacing: 12, runSpacing: 9, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: ShareMTheme.teal),
            onPressed: _chooseDevice,
            icon: const Icon(Icons.send_rounded),
            label: const Text('إرسال ملفات'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70)),
            onPressed: () => setState(() => _page = 2),
            icon: const Icon(Icons.move_to_inbox_rounded),
            label: const Text('استقبال'),
          ),
        ]),
      ]),
    ]),
  );

  Widget _emptyDevices() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Color(0xFFE6F6F3), shape: BoxShape.circle),
          child: const Icon(Icons.radar_rounded,
            size: 51, color: ShareMTheme.teal),
        ),
        const SizedBox(height: 18),
        const Text('جارٍ البحث عن أجهزة قريبة',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        const Text('افتح ShareM على الجهاز الآخر واتصل بنفس شبكة Wi-Fi.\n'
          'يمكنك أيضًا الاتصال يدويًا باستخدام عنوان الجهاز.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.7)),
        const SizedBox(height: 15),
        OutlinedButton.icon(
          onPressed: _manualConnect,
          icon: const Icon(Icons.link_rounded),
          label: const Text('الاتصال بعنوان IP'),
        ),
      ]),
    ),
  );

  Widget _peerCard(NearbyDevice peer) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _sendTo(peer),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFE5F7F4),
              child: Icon(Icons.devices_rounded, color: ShareMTheme.teal)),
            const Spacer(),
            const Icon(Icons.circle, size: 9, color: Color(0xFF24B98E)),
            const SizedBox(width: 5),
            const Text('متصل', style: TextStyle(fontSize: 11)),
          ]),
          const Spacer(),
          Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(peer.endpoint, textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    ),
  );

  Widget _sectionTitle(String title, VoidCallback onTap) =>
    Row(children: [
      Expanded(child: Text(title,
        style: Theme.of(context).textTheme.titleLarge)),
      TextButton(onPressed: onTap, child: const Text('عرض الكل')),
    ]);

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
      _pageHeader('الجهاز والاستقبال', 'معلومات الاتصال وإعدادات ShareM'),
      Card(child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          _infoRow(Icons.phone_android_rounded, 'اسم هذا الجهاز',
            service.deviceName, _rename),
          const Divider(height: 30),
          _infoRow(Icons.wifi_rounded, 'عنوان الاتصال المحلي',
            service.running
              ? service.localAddress + ':' + service.port.toString()
              : 'جاري بدء الخدمة', null),
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
      OutlinedButton.icon(
        onPressed: _manualConnect,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('الاتصال يدويًا بجهاز'),
      ),
      const SizedBox(height: 20),
      const Text('ShareM • إصدار تجريبي 0.1.0',
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

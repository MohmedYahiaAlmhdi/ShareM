import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/lan_transfer_service.dart';
import '../core/qr_pairing.dart';
import '../core/wifi_direct_service.dart';
import 'sharem_theme.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.service,
    required this.wifiDirect, required this.onManualConnect});
  final LanTransferService service;
  final WifiDirectService wifiDirect;
  final VoidCallback onManualConnect;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  bool _connectingQr = false;

  Future<void> _showQr() async {
    await widget.service.refreshLocalAddress();
    if (!mounted) return;
    final service = widget.service;
    if (!service.running || !QrPeer.isLocalIpv4(service.localAddress)) {
      _notify('اتصل بشبكة Wi-Fi محلية أو Wi-Fi Direct أولًا لعرض رمز الاقتران.');
      return;
    }
    final peer = QrPeer(id: service.deviceId, name: service.deviceName,
      ip: service.localAddress, port: service.port);
    await showDialog<void>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('رمز الاتصال بجهازي'),
        content: SizedBox(width: 300, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: QrImageView(data: peer.encode(), version: QrVersions.auto,
                  size: 235, backgroundColor: Colors.white,
                  foregroundColor: ShareMTheme.teal),
              ),
            ),
            const SizedBox(height: 12),
            Text(peer.name, textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SelectableText(peer.endpoint, textDirection: TextDirection.ltr),
            const SizedBox(height: 9),
            const Text('يعمل الرمز على شبكة محلية مشتركة، أو بعد إنشاء اتصال Wi‑Fi Direct.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ],
        )),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: peer.encode()));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) _notify('نُسخت بيانات الاقتران');
            },
            icon: const Icon(Icons.copy_rounded), label: const Text('نسخ الرمز'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _scanQr() async {
    String? value;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _QrScanner()),
      );
      value = result;
    } else {
      value = await _pasteCode();
    }
    if (value == null || !mounted) return;
    final peer = QrPeer.tryParse(value);
    if (peer == null) {
      _notify('رمز QR غير صالح أو ليس من تطبيق ShareM');
      return;
    }
    if (peer.id == widget.service.deviceId) {
      _notify('لا يمكنك الاتصال بجهازك نفسه');
      return;
    }
    setState(() => _connectingQr = true);
    try {
      await widget.service.addManualPeer(peer.endpoint, expectedId: peer.id);
      if (mounted) _notify('تم الاتصال بالجهاز «' + peer.name + '»');
    } catch (e) {
      if (mounted) _notify('تعذر الاتصال: تأكد من الشبكة أو اتصال Wi‑Fi Direct. $e');
    } finally {
      if (mounted) setState(() => _connectingQr = false);
    }
  }

  Future<String?> _pasteCode() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال رمز الاتصال'),
        content: SizedBox(width: 360, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('مسح الكاميرا غير مدعوم على هذا النظام. الصق بيانات QR المنسوخة أو اتصل بعنوان IP.'),
            const SizedBox(height: 16),
            TextField(controller: controller, maxLines: 3,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'sharem://pair?...')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('اتصال')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wifi = widget.wifiDirect;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.service, wifi]),
      builder: (ctx, _) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 24),
        children: [
          Text('اتصال الأجهزة', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 5),
          const Text('اعرض رمز جهازك أو امسح رمز جهاز آخر، أو أنشئ اتصال Wi‑Fi Direct على Android.'),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (ctx, constraints) {
            final narrow = constraints.maxWidth < 510;
            final first = _actionCard(Icons.qr_code_2_rounded, 'عرض رمز جهازي',
              'دع الآخر يمسح الرمز', _showQr);
            final second = _actionCard(Icons.qr_code_scanner_rounded, 'مسح QR',
              'اتصال بالجهاز الذي يعرض الرمز',
              _connectingQr ? null : _scanQr);
            return narrow
              ? Column(children: [first, const SizedBox(height: 12), second])
              : Row(children: [Expanded(child: first),
                  const SizedBox(width: 12), Expanded(child: second)]);
          }),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.wifi_tethering_rounded, color: ShareMTheme.teal),
            const SizedBox(width: 10),
            Expanded(child: Text('Wi‑Fi Direct',
              style: Theme.of(context).textTheme.titleLarge)),
            if (wifi.isAndroid && wifi.available)
              TextButton.icon(
                onPressed: wifi.busy ? null : wifi.discover,
                icon: wifi.busy
                  ? const SizedBox(width: 17, height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.radar_rounded),
                label: const Text('بحث'),
              ),
          ]),
          const SizedBox(height: 8),
          if (!wifi.isAndroid)
            _note('Wi‑Fi Direct متاح حاليًا على Android فقط. '
              'لا يزال QR والاتصال بالشبكة المحلية يعملان هنا.')
          else if (!wifi.available)
            _note('هذه النسخة أو هذا الجهاز لا يوفر Wi‑Fi Direct. '
              'يمكنك استخدام QR عبر Wi‑Fi.')
          else ...[
            if (!wifi.enabled)
              _note('فعّل Wi‑Fi في إعدادات Android، ثم امنح إذن الأجهزة القريبة.'),
            if (wifi.connected)
              Card(child: ListTile(
                leading: const Icon(Icons.check_circle_rounded,
                  color: ShareMTheme.teal),
                title: Text(wifi.groupOwner ? 'جهازك مضيف اتصال مباشر'
                  : 'متصل مباشرة بجهاز آخر'),
                subtitle: Text(wifi.ownerIp == null
                  ? 'جارٍ الحصول على عنوان المجموعة'
                  : 'عنوان المضيف: ' + wifi.ownerIp!),
                trailing: IconButton(
                  tooltip: 'إنهاء اتصال Wi‑Fi Direct',
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: wifi.disconnect,
                ),
              )),
            if (wifi.error != null)
              _note('مشكلة في Wi‑Fi Direct: ' + wifi.error!),
            if (wifi.peers.isEmpty && !wifi.connected)
              _note('اضغط بحث، وانتظر ظهور أجهزة Android الداعمة القريبة. '
                'قد يتطلب الاكتشاف تشغيل خدمات الموقع.')
            else
              for (final peer in wifi.peers)
                Card(child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.phone_android_rounded)),
                  title: Text(peer.name),
                  subtitle: Text(peer.address,
                    textDirection: TextDirection.ltr),
                  trailing: FilledButton(
                    onPressed: wifi.busy || wifi.connected
                      ? null : () => wifi.connect(peer.address),
                    child: const Text('اتصال'),
                  ),
                )),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: widget.onManualConnect,
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('الاتصال بعنوان IP يدويًا'),
          ),
          const SizedBox(height: 16),
          const Text('ملاحظة: QR يعرّف بالجهاز ويختصر كتابة عنوانه. '
            'لا يثبت هوية شخص موثوق، ولا يشفّر نقل الملفات في هذا الإصدار.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _actionCard(IconData icon, String title,
      String description, VoidCallback? callback) =>
    Card(child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: callback,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 23),
        child: Column(children: [
          Icon(icon, size: 46, color: ShareMTheme.teal),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800,
            fontSize: 16)),
          const SizedBox(height: 6),
          Text(description, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12)),
        ]),
      ),
    ));

  Widget _note(String text) => Card(child: Padding(
    padding: const EdgeInsets.all(17),
    child: Text(text),
  ));
}

class _QrScanner extends StatefulWidget {
  const _QrScanner();

  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مسح رمز ShareM')),
    body: SafeArea(child: Stack(children: [
      MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && QrPeer.tryParse(value) != null) {
              _done = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
      Center(child: IgnorePointer(child: Container(
        width: 255, height: 255,
        decoration: BoxDecoration(
          border: Border.all(width: 3, color: ShareMTheme.mint),
          borderRadius: BorderRadius.circular(26),
        ),
      ))),
      const Positioned(
        bottom: 38, left: 16, right: 16,
        child: Text('وجّه الكاميرا إلى رمز QR الظاهر على الجهاز الآخر.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white,
            fontSize: 15, fontWeight: FontWeight.w800)),
      ),
    ])),
  );
}

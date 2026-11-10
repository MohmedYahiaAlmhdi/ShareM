import 'package:flutter/material.dart';
import '../core/update_service.dart';
import '../core/transfer_models.dart';
import 'sharem_theme.dart';

class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key, required this.updates});
  final UpdateService updates;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      final phase = updates.phase;
      final status = switch (phase) {
        UpdatePhase.idle => 'اضغط للتحقق من إصدار جديد',
        UpdatePhase.checking => 'جارٍ فحص تحديثات GitHub…',
        UpdatePhase.current => 'هذا هو أحدث إصدار منشور',
        UpdatePhase.available => 'يتوفر إصدار جديد من ShareM',
        UpdatePhase.downloading => 'جارٍ تنزيل التحديث…',
        UpdatePhase.ready => 'اكتمل التنزيل، جاهز للتثبيت',
        UpdatePhase.installing => 'تابع تثبيت التحديث في Android',
        UpdatePhase.failed => 'تعذر التحقق أو التنزيل',
      };
      final action = phase == UpdatePhase.available ? updates.download :
          phase == UpdatePhase.ready ? updates.install : updates.check;
      final label = phase == UpdatePhase.available ? 'تنزيل الإصدار الجديد' :
          phase == UpdatePhase.ready ? 'تثبيت التحديث' : 'التحقق من التحديثات';
      return Card(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.system_update_alt_rounded,
              color: ShareMTheme.teal, size: 31),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تحديثات ShareM',
                  style: Theme.of(context).textTheme.titleLarge),
                Text('الإصدار الحالي: ' + updates.currentVersion,
                  style: const TextStyle(fontSize: 12)),
              ],
            )),
            if (updates.hasUpdate)
              const Icon(Icons.fiber_new_rounded, color: ShareMTheme.teal),
          ]),
          const SizedBox(height: 14),
          Text(status),
          if (updates.hasUpdate && updates.release != null) ...[
            const SizedBox(height: 8),
            Text('الإصدار الجديد: ' + updates.release!.version,
              style: const TextStyle(fontWeight: FontWeight.w800)),
            if (updates.release!.notes.isNotEmpty)
              Text(updates.release!.notes),
            if (updates.selected != null)
              Text('حجم التنزيل: ' + humanSize(updates.selected!.sizeBytes)),
          ],
          if (phase == UpdatePhase.downloading) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: updates.progress, minHeight: 7,
              borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 5),
            Text((updates.progress * 100).toStringAsFixed(0) + '%',
              textDirection: TextDirection.ltr),
          ],
          if (updates.message != null)
            Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(updates.message!,
                style: const TextStyle(fontSize: 12,
                  color: Colors.deepOrange))),
          const SizedBox(height: 14),
          if (phase == UpdatePhase.downloading)
            OutlinedButton.icon(
              onPressed: updates.cancel,
              icon: const Icon(Icons.close_rounded),
              label: const Text('إلغاء التنزيل'),
            )
          else
            FilledButton.icon(
              onPressed: (phase == UpdatePhase.checking ||
                phase == UpdatePhase.installing ||
                (phase == UpdatePhase.available && !updates.isAndroid))
                ? null : action,
              icon: Icon(phase == UpdatePhase.ready
                  ? Icons.install_mobile_rounded
                  : phase == UpdatePhase.available
                    ? Icons.download_rounded : Icons.refresh_rounded),
              label: Text(label),
            ),
          if (!updates.isAndroid && updates.hasUpdate)
            const Padding(padding: EdgeInsets.only(top: 10),
              child: Text('التحديث داخل التطبيق عبر APK متاح لـAndroid فقط. '
                'تستخدم iOS والحواسيب آليات تثبيت خاصة بكل نظام.',
                style: TextStyle(fontSize: 12))),
          const SizedBox(height: 6),
          const Text('يتطلب Android تأكيد التثبيت. يجب أن تكون التحديثات '
            'موقعة بالمفتاح نفسه للحفاظ على التطبيق والبيانات.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ));
    },
  );
}

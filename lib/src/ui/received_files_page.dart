import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/received_file_catalog.dart';
import '../core/shared_files_inbox.dart';
import '../core/transfer_models.dart';
import 'sharem_theme.dart';

export '../core/received_file_catalog.dart' show isUserReceivedFile;

/// A searchable gallery that only displays verified completed files.
class ReceivedFilesPage extends StatefulWidget {
  const ReceivedFilesPage({super.key, this.onSendAgain});
  final ValueChanged<File>? onSendAgain;

  @override
  State<ReceivedFilesPage> createState() => _ReceivedFilesPageState();
}

class _ReceivedFilesPageState extends State<ReceivedFilesPage> {
  late Future<List<ReceivedFileRecord>> _files = _loadFiles();
  String _query = '';
  ReceivedFileCategory _category = ReceivedFileCategory.all;
  ReceivedFileSort _sort = ReceivedFileSort.newest;
  int _visible = 30;
  final Set<String> _exporting = {};

  static String _categoryLabel(ReceivedFileCategory value) => switch (value) {
    ReceivedFileCategory.all => 'الكل',
    ReceivedFileCategory.images => 'الصور',
    ReceivedFileCategory.videos => 'الفيديو',
    ReceivedFileCategory.audio => 'الصوت',
    ReceivedFileCategory.documents => 'المستندات',
    ReceivedFileCategory.archives => 'المضغوطة',
    ReceivedFileCategory.apps => 'التطبيقات',
    ReceivedFileCategory.other => 'أخرى',
  };

  static String _sortLabel(ReceivedFileSort value) => switch (value) {
    ReceivedFileSort.newest => 'الأحدث',
    ReceivedFileSort.oldest => 'الأقدم',
    ReceivedFileSort.name => 'الاسم',
    ReceivedFileSort.largest => 'الحجم',
  };

  Future<List<ReceivedFileRecord>> _loadFiles() async {
    final directory = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path, 'ShareM', 'Received'));
    if (!await directory.exists()) return [];
    final records = <ReceivedFileRecord>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File ||
          !isUserReceivedFile(p.basename(entry.path))) continue;
      try {
        final stat = await entry.stat();
        records.add(ReceivedFileRecord(
          path: entry.path, sizeBytes: stat.size, modified: stat.modified));
      } catch (_) {
        // A file may have been removed while enumerating.
      }
      if (records.length >= 2000) break;
    }
    return records;
  }

  void _refresh() {
    if (mounted) setState(() {
      _visible = 30;
      _files = _loadFiles();
    });
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share(File file) async {
    try {
      if (!await file.exists()) throw const FileSystemException('Missing file');
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2, size.height / 2, 1, 1),
      ));
    } catch (_) {
      _message('تعذّر فتح مشاركة الملف. حدّث القائمة وحاول من جديد.');
    }
  }

  Future<void> _sendAgain(File file) async {
    if (widget.onSendAgain == null) return;
    if (!await file.exists()) {
      _message('لم يعد الملف موجودًا. حدّث القائمة.');
      return;
    }
    widget.onSendAgain!(file);
  }

  Future<void> _preview(File file) async {
    if (!await file.exists()) {
      _message('الصورة غير موجودة.');
      _refresh();
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            width: size.width * .9,
            height: size.height * .72,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(child: Text(p.basename(file.path),
                    overflow: TextOverflow.ellipsis, maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: () => Navigator.pop(ctx),
                    tooltip: 'إغلاق',
                    icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Expanded(child: InteractiveViewer(
                minScale: .7, maxScale: 4,
                child: Center(child: Image.file(file,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                    const Text('تعذّرت معاينة الصورة'))),
              )),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(onPressed: () => _share(file),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('مشاركة')),
                    if (widget.onSendAgain != null)
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendAgain(file);
                        },
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('إرسال عبر ShareM')),
                  ]),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Future<void> _saveToDownloads(File file) async {
    if (_exporting.contains(file.path)) return;
    setState(() => _exporting.add(file.path));
    try {
      await SharedFilesInbox.saveToDownloads(file.path);
      _message('تم الحفظ في التنزيلات / ShareM');
    } catch (e) {
      _message('تعذّر الحفظ في التنزيلات: ' + e.toString());
    } finally {
      if (mounted) setState(() => _exporting.remove(file.path));
    }
  }

  Future<void> _delete(File file) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الملف المستلم؟'),
        content: Text('سيُحذف ' + p.basename(file.path) +
          ' من التطبيق فقط. النسخ الموجودة في التنزيلات لن تتأثر.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف نهائي')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await file.delete();
      _message('تم حذف الملف من ShareM');
      _refresh();
    } catch (_) {
      _message('تعذّر حذف الملف. حاول مجددًا.');
    }
  }

  IconData _iconFor(ReceivedFileCategory type) => switch (type) {
    ReceivedFileCategory.images => Icons.image_outlined,
    ReceivedFileCategory.videos => Icons.movie_outlined,
    ReceivedFileCategory.audio => Icons.headphones_outlined,
    ReceivedFileCategory.documents => Icons.description_outlined,
    ReceivedFileCategory.archives => Icons.folder_zip_outlined,
    ReceivedFileCategory.apps => Icons.android_rounded,
    _ => Icons.insert_drive_file_outlined,
  };

  Widget _thumbnail(ReceivedFileRecord item) {
    if (item.category == ReceivedFileCategory.images) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(item.path),
          width: 46, height: 46, fit: BoxFit.cover, cacheWidth: 120,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 46, height: 46,
            child: Icon(Icons.broken_image_outlined,
              color: ShareMTheme.teal)),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: ShareMTheme.teal.withAlpha(20),
      child: Icon(_iconFor(item.category), color: ShareMTheme.teal));
  }

  Widget _tile(ReceivedFileRecord item) {
    final file = File(item.path);
    return Card(
      key: ValueKey('received-' + item.path),
      child: ListTile(
        leading: _thumbnail(item),
        title: Text(item.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(humanSize(item.sizeBytes)),
        onTap: () => item.category == ReceivedFileCategory.images
          ? _preview(file) : _share(file),
        trailing: _exporting.contains(item.path)
          ? const SizedBox(height: 24, width: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<String>(
            tooltip: 'خيارات الملف',
            onSelected: (value) {
              if (value == 'resend') _sendAgain(file);
              if (value == 'share') _share(file);
              if (value == 'downloads') _saveToDownloads(file);
              if (value == 'delete') _delete(file);
            },
            itemBuilder: (_) => [
              if (widget.onSendAgain != null)
                const PopupMenuItem(value: 'resend',
                  child: Text('إرسال عبر ShareM')),
              const PopupMenuItem(value: 'share',
                child: Text('مشاركة مع تطبيق آخر')),
              if (Platform.isAndroid)
                const PopupMenuItem(value: 'downloads',
                  child: Text('حفظ في التنزيلات')),
              const PopupMenuItem(value: 'delete',
                child: Text('حذف من ShareM')),
            ],
          ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Expanded(child: Text('ملفاتي المستلمة',
          style: Theme.of(context).textTheme.titleLarge)),
        IconButton(onPressed: _refresh,
          tooltip: 'تحديث الملفات المستلمة',
          icon: const Icon(Icons.refresh_rounded)),
      ]),
      const SizedBox(height: 12),
      TextField(
        onChanged: (value) => setState(() {
          _query = value;
          _visible = 30;
        }),
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'ابحث في الملفات المستقبلة',
          prefixIcon: Icon(Icons.search_rounded)),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final type in ReceivedFileCategory.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 7),
              child: ChoiceChip(
                label: Text(_categoryLabel(type)),
                selected: _category == type,
                onSelected: (_) => setState(() {
                  _category = type;
                  _visible = 30;
                }),
              )),
        ]),
      ),
      const SizedBox(height: 10),
      FutureBuilder<List<ReceivedFileRecord>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return const Card(child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('تعذّرت قراءة الملفات. تحقق من مساحة التخزين.')));
          }
          final items = snapshot.data ?? <ReceivedFileRecord>[];
          final shown = filterReceivedFiles(items,
            query: _query, category: _category, sort: _sort);
          if (items.isEmpty) {
            return const Card(child: Padding(
              padding: EdgeInsets.all(25),
              child: Column(children: [
                Icon(Icons.folder_open_rounded,
                  color: ShareMTheme.teal, size: 42),
                SizedBox(height: 8),
                Text('لم تستقبل ملفات بعد',
                  style: TextStyle(fontWeight: FontWeight.w800)),
                Text('تظهر الملفات هنا بعد قبول أول عملية استقبال.'),
              ])));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(
                  shown.length.toString() + ' ملف من أصل ' +
                    items.length.toString(),
                  style: Theme.of(context).textTheme.bodySmall)),
                DropdownButton<ReceivedFileSort>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value != null) setState(() {
                      _sort = value;
                      _visible = 30;
                    });
                  },
                  items: [
                    for (final value in ReceivedFileSort.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_sortLabel(value)),
                      ),
                  ],
                ),
              ]),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('لا توجد ملفات تطابق البحث أو التصنيف.'))
              else ...[
                for (final item in shown.take(_visible)) _tile(item),
                if (shown.length > _visible)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _visible += 30),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text('عرض المزيد (' +
                      (shown.length - _visible).toString() + ' متبقي)'),
                  ),
              ],
            ],
          );
        },
      ),
    ],
  );
}

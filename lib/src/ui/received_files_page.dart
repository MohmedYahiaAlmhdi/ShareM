import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/transfer_models.dart';
import 'sharem_theme.dart';

bool isUserReceivedFile(String name) =>
    name.isNotEmpty &&
    !(name.startsWith('.sharem-') && name.endsWith('.part'));

class ReceivedFilesPage extends StatefulWidget {
  const ReceivedFilesPage({super.key});

  @override
  State<ReceivedFilesPage> createState() => _ReceivedFilesPageState();
}

class _ReceivedFile {
  const _ReceivedFile(this.file, this.stat);
  final File file;
  final FileStat stat;
}

class _ReceivedFilesPageState extends State<ReceivedFilesPage> {
  late Future<List<_ReceivedFile>> _files = _loadFiles();

  Future<List<_ReceivedFile>> _loadFiles() async {
    final root = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path,
      'ShareM', 'Received'));
    if (!await root.exists()) return [];
    final result = <_ReceivedFile>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File ||
          !isUserReceivedFile(p.basename(entity.path))) continue;
      try {
        result.add(_ReceivedFile(entity, await entity.stat()));
      } catch (_) {
        // A file may disappear between listing and reading metadata.
      }
      if (result.length >= 500) break;
    }
    result.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    return result;
  }

  void _refresh() {
    if (mounted) setState(() => _files = _loadFiles());
  }

  Future<void> _share(File file) async {
    try {
      if (!await file.exists()) throw const FileSystemException(
        'File no longer exists');
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2, size.height / 2, 1, 1),
      ));
    } catch (_) {
      if (mounted) _message('تعذّر مشاركة الملف. جرّب تحديث القائمة.');
    }
  }

  Future<void> _delete(File file) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('حذف الملف المستلم؟'),
        content: Text('سيُحذف «' + p.basename(file.path) +
          '» من مساحة التطبيق. لا يمكن التراجع عن الحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('حذف نهائي')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await file.delete();
      _message('تم حذف الملف');
      _refresh();
    } catch (_) {
      _message('تعذّر حذف الملف. حاول مجددًا.');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)));
  }

  IconData _iconFor(String name) {
    final ext = p.extension(name).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (['.mp4', '.mkv', '.webm', '.mov'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['.mp3', '.wav', '.m4a', '.aac', '.ogg'].contains(ext)) {
      return Icons.headphones_outlined;
    }
    if (ext == '.apk') return Icons.android_rounded;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(children: [
        Expanded(child: Text('ملفاتي المستلمة',
          style: Theme.of(context).textTheme.titleLarge)),
        IconButton(
          tooltip: 'تحديث الملفات المستلمة',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded)),
      ]),
      const SizedBox(height: 9),
      FutureBuilder<List<_ReceivedFile>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return const Card(child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('تعذّر قراءة الملفات. تحقق من مساحة التخزين.')));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Card(child: Padding(
              padding: EdgeInsets.all(25),
              child: Column(children: [
                Icon(Icons.folder_open_rounded,
                  color: ShareMTheme.teal, size: 42),
                SizedBox(height: 9),
                Text('لم تستقبل أي ملفات بعد',
                  style: TextStyle(fontWeight: FontWeight.w800)),
                Text('ستظهر الملفات هنا بعد قبول أول عملية استقبال.'),
              ])));
          }
          return Column(children: [
            for (final item in items)
              Card(child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: ShareMTheme.teal.withAlpha(20),
                  child: Icon(_iconFor(item.file.path),
                    color: ShareMTheme.teal)),
                title: Text(p.basename(item.file.path),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(humanSize(item.stat.size)),
                trailing: Wrap(spacing: 0, children: [
                  IconButton(
                    tooltip: 'مشاركة الملف',
                    onPressed: () => _share(item.file),
                    icon: const Icon(Icons.ios_share_rounded)),
                  IconButton(
                    tooltip: 'حذف الملف',
                    onPressed: () => _delete(item.file),
                    icon: const Icon(Icons.delete_outline_rounded)),
                ]),
              )),
          ]);
        },
      ),
    ],
  );
}

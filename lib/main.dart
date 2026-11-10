import 'package:flutter/material.dart';
import 'src/core/lan_transfer_service.dart';
import 'src/ui/home_page.dart';
import 'src/ui/sharem_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShareMApp(service: LanTransferService()));
}

class ShareMApp extends StatelessWidget {
  const ShareMApp({super.key, required this.service});
  final LanTransferService service;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ShareM',
    debugShowCheckedModeBanner: false,
    theme: ShareMTheme.light,
    darkTheme: ShareMTheme.dark,
    themeMode: ThemeMode.light,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: ShareMHomePage(service: service),
    ),
  );
}

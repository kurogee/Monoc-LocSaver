import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:monoc_locsaver/screens/home_screen.dart';
import 'package:monoc_locsaver/services/location_service.dart';
import 'package:monoc_locsaver/services/photo_watcher_service.dart';
import 'package:monoc_locsaver/services/nearby_service.dart';
import 'package:monoc_locsaver/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocationService().initialize();
  // 写真パーミッションをリクエスト（ユーザーの操作が必要な場合がある）
  await PhotoWatcherService.instance.requestPermission();
  // バディ探索サービスの初期化
  await NearbyService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monoc LocSaver',
      theme: AppTheme.darkTheme, // 白黒基調のダークテーマ
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ja', 'JP'),
    );
  }
}

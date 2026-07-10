import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'services/stock_api_service.dart';
import 'services/notification_service.dart';
import 'database/database_helper.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  StockApiService().init();
  await DatabaseHelper().database;
  await NotificationService().init();
  await NotificationService().requestPermission();

  runApp(const ProviderScope(child: ZeroCostHoldingApp()));
}

class ZeroCostHoldingApp extends StatelessWidget {
  const ZeroCostHoldingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '零成本持仓助手',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      home: const HomeScreen(key: ValueKey('home-screen-root')),
      routes: {
        '/search': (_) => const SearchScreen(),
      },
    );
  }
}

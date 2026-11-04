import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/browser_provider.dart';
import 'providers/download_provider.dart';
import 'providers/script_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => ScriptProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 仅监听深色模式状态变化，避免网页加载进度更新时整棵应用树高频重建
    return Selector<BrowserProvider, bool>(
      selector: (_, provider) => provider.isDarkMode,
      builder: (context, isDarkMode, child) {
        return MaterialApp(
          navigatorKey: BrowserProvider.navigatorKey,
          title: 'Auok浏览器',
          // 中文本地化配置
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'), // 简体中文
            Locale('en', 'US'), // 英文（备用）
          ],
          theme: ThemeData(
            brightness: isDarkMode ? Brightness.dark : Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: isDarkMode ? Colors.black : Colors.white,
            appBarTheme: AppBarTheme(
              backgroundColor: isDarkMode ? Colors.grey[900] : Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          home: const BrowserHomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

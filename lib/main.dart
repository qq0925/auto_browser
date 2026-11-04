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
    return Consumer<BrowserProvider>(
      builder: (context, browserProvider, child) {
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
            brightness:
                browserProvider.isDarkMode ? Brightness.dark : Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor:
                browserProvider.isDarkMode ? Colors.black : Colors.white,
            appBarTheme: AppBarTheme(
              backgroundColor:
                  browserProvider.isDarkMode ? Colors.grey[900] : Colors.blue,
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

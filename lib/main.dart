import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/browser_provider.dart';
import 'providers/script_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowserProvider()),
        ChangeNotifierProvider(create: (_) => ScriptProvider()),
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
          title: 'Auok浏览器',
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

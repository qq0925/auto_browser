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
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
          ),
          home: const BrowserHomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

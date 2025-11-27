import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/browser_provider.dart';
import 'providers/script_provider.dart';

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
        return CupertinoApp(
          title: 'Auok浏览器',
          theme: CupertinoThemeData(
            primaryColor: CupertinoColors.systemBlue,
            brightness:
                browserProvider.isDarkMode ? Brightness.dark : Brightness.light,
          ),
          home: const BrowserHomePage(),
        );
      },
    );
  }
}

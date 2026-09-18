import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PicoTabsApp());
}

class PicoTabsApp extends StatelessWidget {
  const PicoTabsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'picotabs',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}

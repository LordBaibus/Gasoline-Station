import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'pages/homepage.dart';
import 'pages/settings.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(
    ProviderScope(
      child: LiquidGlassWidgets.wrap(child: const MyApp()),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int selectedIndex = 0;

  static const List<Widget> _pages = [
    Homepage(),
    Settings(),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: GulfColors.orange,
        scaffoldBackgroundColor: GulfColors.blue,
        barBackgroundColor: GulfColors.blueDark,
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(color: GulfColors.white),
        ),
      ),
      home: GlassScaffold(
        backgroundColor: GulfColors.blue,
        body: SafeArea(child: _pages[selectedIndex]),
        bottomBar: GlassTabBar.bottom(
          tabs: const [
            GlassTab(icon: Icon(CupertinoIcons.home)),
            GlassTab(icon: Icon(CupertinoIcons.settings)),
          ],
          selectedIndex: selectedIndex,
          onTabSelected: (tab) {
            setState(() {
              selectedIndex = tab;
            });
          },
          selectedIconColor: GulfColors.orange,
          unselectedIconColor: GulfColors.whiteMuted,
          indicatorColor: GulfColors.white.withValues(alpha: 0.16),
        ),
      ),
    );
  }
}
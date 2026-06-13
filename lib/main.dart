import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
import 'package:musicplayer/pages/settings_page.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/audio_settings_service.dart';
import 'package:musicplayer/services/audio_focus_service.dart';
import 'package:musicplayer/pages/list.dart';
import 'package:musicplayer/pages/album_page.dart';
import 'package:musicplayer/pages/artist_list.dart';
import 'package:musicplayer/pages/artist_page.dart';
import 'package:musicplayer/pages/browse_page.dart';
import 'package:musicplayer/pages/home_page.dart';
import 'package:musicplayer/pages/music_list.dart';
import 'package:musicplayer/pages/music_player.dart';
import 'package:musicplayer/pages/radio.dart';
import 'package:musicplayer/pages/search_page.dart';
import 'package:musicplayer/webView/webViewContainer.dart';
import 'package:flutter/services.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/library_page.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: true,
    );
  }

  if (!kIsWeb) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  await ThemeController.init();
  await AudioSettingsService.init();
  AudioService.initialize();
  AudioFocusService.initialize();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Permission.storage.request();
    await Permission.audio.request();
  }

  runApp(const MyApp());
}

void applyEdgeToEdge() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}

class MyScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) applyEdgeToEdge();
    if (state == AppLifecycleState.paused) {
      AudioFocusService.onFocusLoss(transient: false);
    }
    if (state == AppLifecycleState.resumed) {
      AudioFocusService.onFocusGain();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyScrollBehavior(),
      builder: (context, child) {
        applyEdgeToEdge();
        return child ?? const SizedBox.shrink();
      },
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(),
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        fontFamily: 'SF Pro Display',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'SF Pro Display'),
          displayMedium: TextStyle(fontFamily: 'SF Pro Display'),
          displaySmall: TextStyle(fontFamily: 'SF Pro Display'),
          headlineLarge: TextStyle(fontFamily: 'SF Pro Display'),
          headlineMedium: TextStyle(fontFamily: 'SF Pro Display'),
          headlineSmall: TextStyle(fontFamily: 'SF Pro Display'),
          titleLarge: TextStyle(fontFamily: 'SF Pro Display'),
          titleMedium: TextStyle(fontFamily: 'SF Pro Display'),
          titleSmall: TextStyle(fontFamily: 'SF Pro Display'),
          bodyLarge: TextStyle(fontFamily: 'SF Pro Display'),
          bodyMedium: TextStyle(fontFamily: 'SF Pro Display'),
          bodySmall: TextStyle(fontFamily: 'SF Pro Display'),
          labelLarge: TextStyle(fontFamily: 'SF Pro Display'),
          labelMedium: TextStyle(fontFamily: 'SF Pro Display'),
          labelSmall: TextStyle(fontFamily: 'SF Pro Display'),
        ),
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/firstpage',
      routes: {
        '/settings': (context) => const SettingsPage(),
        '/list_test': (context) => const WebView(child: ListTest()),
        '/firstpage': (context) => const WebView(child: FirstPage()),
        '/browse': (context) => const WebView(child: BrowsePage()),
        '/radio': (context) => const WebView(child: RadioPage()),
        '/library': (context) => const WebView(child: LibraryPage()),
        '/search': (context) => const WebView(child: SearchPage()),
        '/home': (context) => const WebView(child: HomePage()),
        '/album': (context) => const WebView(child: AlbumPage()),
        '/artist': (context) => const WebView(child: ArtistPage()),
        '/artistlist': (context) => const WebView(child: ArtistList()),
        '/musiclist': (context) => const WebView(child: MusicList()),
        '/player': (context) => const WebView(child: MusicPlayer()),
      },
    );
  }
}

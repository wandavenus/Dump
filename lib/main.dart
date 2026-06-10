import 'dart:io';
import 'package:flutter/material.dart';
import 'package:musicplayer/Bottom%20NavBar/bottom_nav.dart';
import 'package:musicplayer/pages/settings_page.dart';
import 'package:musicplayer/services/audio_service.dart';
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
import 'package:musicplayer/themes/apple_music_blur.dart';
import 'package:musicplayer/themes/theme_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/library_page.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.musicplayer.channel.audio',
    androidNotificationChannelName: 'Music Playback',
    androidNotificationIcon: 'drawable/ic_notification',
    androidNotificationOngoing: true,
  );

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  await ThemeController.init();
  AudioService.initialize();

  if (Platform.isAndroid) {
    await Permission.storage.request();
    await Permission.audio.request();
  }

  runApp(const MyApp());
}

class MyScrollBehavior extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppleMusicColors.accent,
          surface: AppleMusicColors.backgroundElevated,
          onSurface: AppleMusicColors.label,
        ),
        scaffoldBackgroundColor: AppleMusicColors.background,
        canvasColor: Colors.transparent,
        cardColor: AppleMusicColors.backgroundElevated,
        dividerColor: AppleMusicColors.separator,
        splashColor: Colors.white10,
        highlightColor: Colors.white10,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppleMusicColors.label,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppleMusicColors.label,
            fontFamily: 'SF Pro Display',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          modalBackgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppleMusicColors.regularMaterialTint,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppleMusicRadii.card),
          ),
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

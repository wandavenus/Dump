import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/common_actions.dart';
import '../widgets/pages/album_sections.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final theme = Theme.of(context);
    if (route == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
      );
    }
    final args = route.settings.arguments as Map<String, dynamic>;

    final album = args['album'] as LocalSong;
    final songs = args['songs'] as List<LocalSong>;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.arrow_left,
            color: colorScheme.primary,
            size: 28,
          ),
        ),
        actions: const [CommonActions()],
      ),
      body: AlbumPageContent(album: album, songs: songs),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/common_actions.dart';
import '../widgets/pages/artist_sections.dart';

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final theme = Theme.of(context);

    if (route == null) {
      return Scaffold(backgroundColor: theme.scaffoldBackgroundColor);
    }

    final songs = route.settings.arguments as List<LocalSong>;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: FadingTitleAppBar(
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.arrow_left,
            color: theme.colorScheme.primary,
            size: 28,
          ),
        ),
        actions: const [CommonActions()],
      ),
      body: ArtistPageContent(songs: songs),
    );
  }
}

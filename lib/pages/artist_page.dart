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
    final songs = ModalRoute.of(context)!.settings.arguments as List<LocalSong>;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: FadingTitleAppBar(
        scrollOffset: 100,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.arrow_left,
            color: Color(0xFFF92D48),
            size: 28,
          ),
        ),
        actions: const [CommonActions()],
      ),
      body: ArtistPageContent(songs: songs),
    );
  }
}

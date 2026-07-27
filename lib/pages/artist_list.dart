import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:musicplayer/extensions/localization_extension.dart';

import '../widgets/common/scrolling_page_chrome.dart';
import '../widgets/common_actions.dart';
import '../widgets/pages/artist_list_sections.dart';

class ArtistList extends StatefulWidget {
  const ArtistList({super.key});

  @override
  State<ArtistList> createState() => _ArtistListState();
}

class _ArtistListState extends State<ArtistList> {
  final _scroll = ScrollController();
  final _offsetNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  // Clamp ke 140px — batas atas animasi AppBar. Di atasnya output visual
  // identik, jadi notifier tidak perlu diupdate.
  static const double _kAnimEnd = 140.0;

  void _onScroll() {
    final clamped = _scroll.offset.clamp(0.0, _kAnimEnd);
    if (clamped != _offsetNotifier.value) _offsetNotifier.value = clamped;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FadingTitleAppBar(
        title: context.l10n.favoriteArtists,
        scrollOffsetListenable: _offsetNotifier,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: 8),
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.arrow_left,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
        ),
        actions: const [CommonActions()],
      ),
      body: ArtistListContent(scrollController: _scroll),
    );
  }
}

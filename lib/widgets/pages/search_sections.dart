import 'package:flutter/material.dart';

import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../services/media_store_service.dart';
import '../../utils/sample_music_data.dart';
import '../common_actions.dart';
import '../player/player_panel_controller.dart';
import '../song_artwork.dart';

// ─── Main entry point ─────────────────────────────────────────────────────────

class SearchSlivers extends StatefulWidget {
  const SearchSlivers({super.key, required this.scrollOffset});

  final double scrollOffset;

  @override
  State<SearchSlivers> createState() => _SearchSliversState();
}

class _SearchSliversState extends State<SearchSlivers> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<LocalSong> _allSongs = [];
  List<LocalSong> _results = [];
  bool _isSearching = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    setState(() => _loading = true);
    final songs = await MediaStoreService.getSongs();
    if (mounted) setState(() { _allSongs = songs; _loading = false; });
  }

  void _onQueryChanged() {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() { _results = []; _isSearching = false; });
      return;
    }
    final filtered = _allSongs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q);
    }).toList();
    setState(() { _results = filtered; _isSearching = true; });
  }

  void _clearSearch() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() { _results = []; _isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        _SearchAppBar(scrollOffset: widget.scrollOffset),
        SliverToBoxAdapter(child: _SearchTitle(isSearching: _isSearching)),
        SliverToBoxAdapter(
          child: _SearchBar(
            controller: _controller,
            focusNode: _focusNode,
            isSearching: _isSearching,
            loading: _loading,
            onClear: _clearSearch,
          ),
        ),
        if (_isSearching)
          _SearchResultsSliver(
            results: _results,
            query: _controller.text.trim(),
            allSongs: _allSongs,
          )
        else
          const SearchCategoryGrid(),
      ],
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────────

class _SearchAppBar extends StatelessWidget {
  const _SearchAppBar({required this.scrollOffset});

  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.black,
      automaticallyImplyLeading: false,
      surfaceTintColor: Colors.transparent,
      title: Transform.translate(
        offset: Offset(0, (1 - (scrollOffset / 100).clamp(0.0, 1.0)) * 40),
        child: Opacity(
          opacity: ((((scrollOffset - 25) / 25).clamp(0.0, 1.0)) * 1.5)
              .clamp(0.0, 1.0),
          child: const Text('Cari',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Opacity(
          opacity: (scrollOffset / 140).clamp(0.0, 1.0),
          child: Container(height: 0.9, color: const Color(0xFF48484A)),
        ),
      ),
      actions: const [CommonActions()],
    );
  }
}

// ─── Title ────────────────────────────────────────────────────────────────────

class _SearchTitle extends StatelessWidget {
  final bool isSearching;
  const _SearchTitle({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSearching ? 0 : 1,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          'Cari',
          style: TextStyle(
              fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final bool loading;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.loading,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, color: Color(0xFF8E8E93), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: const Color(0xFFF92D48),
                decoration: const InputDecoration(
                  hintText: 'Artis, Lagu, Album, dan lainnya',
                  hintStyle:
                      TextStyle(color: Color(0xFF8E8E93), fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => focusNode.unfocus(),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              )
            else if (isSearching)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.cancel, color: Color(0xFF8E8E93), size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Search Results ───────────────────────────────────────────────────────────

class _SearchResultsSliver extends StatelessWidget {
  final List<LocalSong> results;
  final List<LocalSong> allSongs;
  final String query;

  const _SearchResultsSliver({
    required this.results,
    required this.allSongs,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, color: Color(0xFF48484A), size: 48),
              const SizedBox(height: 12),
              Text(
                'Tidak ada hasil untuk "$query"',
                style: const TextStyle(
                    color: Color(0xFF8E8E93), fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final song = results[i];
          final indexInAll = allSongs.indexOf(song);
          return _SearchResultTile(
            song: song,
            playlist: allSongs,
            index: indexInAll >= 0 ? indexInAll : 0,
          );
        },
        childCount: results.length,
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final LocalSong song;
  final List<LocalSong> playlist;
  final int index;

  const _SearchResultTile({
    required this.song,
    required this.playlist,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await AudioService.playSongAt(playlist: playlist, index: index);
        PlayerPanelController.instance.open();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SongArtwork(
              songId: song.id,
              size: 48,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${song.artist} · ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF8E8E93), fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.play_arrow,
                color: Color(0xFF48484A), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Category Grid ────────────────────────────────────────────────────────────

class SearchCategoryGrid extends StatelessWidget {
  const SearchCategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _SearchCategoryTile(category: searchCategories[index]),
          childCount: searchCategories.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.3,
        ),
      ),
    );
  }
}

class _SearchCategoryTile extends StatelessWidget {
  const _SearchCategoryTile({required this.category});

  final Map category;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(category['image'], fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.1)
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Text(
              category['title'],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

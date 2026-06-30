part of '../search_sections.dart';

class _SearchSliversState extends State<SearchSlivers>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  // NOT requesting focus automatically — keyboard only appears on explicit tap
  final FocusNode _focusNode = FocusNode();

  List<LocalSong> _allSongs = [];
  List<LocalSong> _results = [];
  bool _isSearching = false;
  bool _loading = false;

  @override
  bool get wantKeepAlive => false; // Don't preserve keyboard state on tab switch

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void deactivate() {
    // Dismiss keyboard when navigating away (tab switch / route pop)
    _focusNode.unfocus();
    super.deactivate();
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
    if (mounted) {
      setState(() {
        _allSongs = songs;
        _loading = false;
      });
    }
  }

  void _onQueryChanged() {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    final filtered =
        _allSongs.where((s) {
          return s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q) ||
              s.album.toLowerCase().contains(q);
        }).toList();
    setState(() {
      _results = filtered;
      _isSearching = true;
    });
  }

  void _clearSearch() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _results = [];
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../extensions/song_map_extensions.dart';
import '../../models/local_song.dart';
import '../../services/audio_service.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../../utils/sample_music_data.dart';
import '../common/scrolling_page_chrome.dart';
import '../song_artwork.dart';

class HomePageContent extends StatelessWidget {
const HomePageContent({super.key});
@override
Widget build(BuildContext context) {
return SingleChildScrollView(
physics: const ClampingScrollPhysics(),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const LargePageTitle(title: 'Beranda', align: false),
const HeaderDivider(),
const _TopPicksSection(),
const SectionTitle(title: 'Recently Played', routeName: '/musiclist'),
const _RecentlyPlayedSection(),
const SectionTitle(title: 'Favourite Artists', routeName: '/artistlist'),
const _FavoriteArtistsSection(),
],
),
);
}
}
class _RecentlyPlayedSection extends StatefulWidget {
const _RecentlyPlayedSection();
@override
State<_RecentlyPlayedSection> createState() => _RecentlyPlayedSectionState();
}
class _RecentlyPlayedSectionState extends State<_RecentlyPlayedSection> {
List<LocalSong> _recentSongs = [];
bool _isLoading = true;
@override
void initState() {
super.initState();
_loadRecentlyPlayed();
}
Future<void> _loadRecentlyPlayed() async {
try {
final recentIds = await HistoryService.getRecentlyPlayedIds();
final allSongs = await MediaStoreService.getSongs();
final songMap = <dynamic, LocalSong>{};
for (var song in allSongs) {
songMap[song.id] = song;
}
final List<LocalSong> recentSongs = [];
for (var id in recentIds) {
if (songMap.containsKey(id)) {
recentSongs.add(songMap[id]!);
}
}
if (mounted) {
setState(() {
_recentSongs = recentSongs;
_isLoading = false;
});
}
} catch (e) {
if (mounted) {
setState(() {
_isLoading = false;
});
}
}
}
@override
Widget build(BuildContext context) {
if (_isLoading) {
return const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()));
}
if (_recentSongs.isEmpty) {
return const SizedBox(height: 250, child: Center(child: Text('No recently played songs')));
}
return SizedBox(
height: 250,
child: ListView.builder(
scrollDirection: Axis.horizontal,
padding: const EdgeInsets.all(10),
itemCount: _recentSongs.length,
itemBuilder: (context, index) {
final song = _recentSongs[index];
return InkWell(
onTap: () async {
await AudioService.playSongAt(playlist: _recentSongs, index: index);
if (!context.mounted) return;
Navigator.pushNamed(context, '/player');
},
child: Container(
margin: const EdgeInsets.only(right: 10, left: 6),
child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 10), ClipPath(clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: SizedBox(height: 170, width: 170, child: SongArtwork(songId: song.id, size: 170, borderRadius: BorderRadius.circular(10)))), const Padding(padding: EdgeInsets.only(top: 2.5)), SizedBox(width: 165, child: Text(song.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white))), Text(song.artist, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey))]),
),
);
},
),
);
}
}
class _TopPicksSection extends StatelessWidget {
const _TopPicksSection();
@override
Widget build(BuildContext context) { return Column(); }
}
class _FavoriteArtistsSection extends StatelessWidget { const _FavoriteArtistsSection(); @override Widget build(BuildContext context){ return const SizedBox(); }}
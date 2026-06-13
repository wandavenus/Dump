import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../extensions/song_map_extensions.dart';
import '../../models/local_song.dart';
import '../../services/history_service.dart';
import '../../services/media_store_service.dart';
import '../../utils/sample_music_data.dart';
import '../common/scrolling_page_chrome.dart';
import '../widgets/song_artwork.dart';
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
return const SizedBox(
height: 250,
child: Center(child: CircularProgressIndicator()),
);
}
if (_recentSongs.isEmpty) {
return const SizedBox(
height: 250,
child: Center(child: Text('No recently played songs')),
);
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
onTap: () {
Navigator.pushNamed(
context,
'/player',
arguments: {
'index': index,
'songs': _recentSongs,
},
);
},
child: Container(
margin: const EdgeInsets.only(right: 10, left: 6),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const SizedBox(height: 10),
ClipPath(
clipper: ShapeBorderClipper(
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(10),
),
),
child: SizedBox(
height: 170,
width: 170,
child: SongArtwork(song: song),
),
),
const Padding(padding: EdgeInsets.only(top: 2.5)),
SizedBox(
width: 165,
child: Text(
song.title,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
fontWeight: FontWeight.normal,
fontSize: 15,
color: Colors.white,
),
),
),
Text(
song.artist,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
fontWeight: FontWeight.normal,
fontSize: 12,
color: Colors.grey,
),
),
],
),
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
Widget build(BuildContext context) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Padding(
padding: EdgeInsets.only(left: 16, top: 9),
child: Text('Top Picks For You',
style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
),
SizedBox(
height: 371,
child: ListView.builder(
scrollDirection: Axis.horizontal,
padding: const EdgeInsets.all(10),
itemCount: homeTopPicks.length,
itemBuilder: (context, index) => _TopPickCard(index: index),
),
),
],
);
}
}
class _TopPickCard extends StatelessWidget {
const _TopPickCard({required this.index});
final int index;
@override
Widget build(BuildContext context) {
final pick = homeTopPicks[index];
return InkWell(
onTap: () => Navigator.pushNamed(context, '/album', arguments: {'index': index}),
child: Container(
margin: const EdgeInsets.only(right: 10, left: 6),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(pick['topMsg'],
style: const TextStyle(
color: Color.fromARGB(255, 153, 153, 153), fontSize: 15)),
const SizedBox(height: 7),
ClipPath(
clipper: const ShapeBorderClipper(
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.only(
topLeft: Radius.circular(15),
topRight: Radius.circular(15),
),
),
),
child: CachedNetworkImage(
placeholder: (context, url) => const CircularProgressIndicator(),
errorWidget: (context, url, error) => const Icon(Icons.error),
imageUrl: pick['image'],
height: 250,
width: 250,
fit: BoxFit.cover,
),
),
ClipPath(
clipper: const ShapeBorderClipper(
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.only(
bottomLeft: Radius.circular(15),
bottomRight: Radius.circular(15),
),
),
),
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 10),
height: 70,
width: 250,
decoration: const BoxDecoration(
gradient: LinearGradient(
colors: [Color.fromARGB(255, 83, 83, 83), Color.fromARGB(255, 36, 36, 36)],
stops: [0, 1],
begin: Alignment.topRight,
end: Alignment.bottomLeft,
),
),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
const Padding(padding: EdgeInsets.only(top: 1)),
Text(pick['title'],
style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
overflow: TextOverflow.ellipsis),
Text(pick['artist'], overflow: TextOverflow.ellipsis),
],
),
),
),
],
),
),
);
}
}
class SongCarousel extends StatelessWidget {
const SongCarousel({
super.key,
required this.songs,
this.itemCount,
this.passSongsToPlayer = false,
});
final List songs;
final int? itemCount;
final bool passSongsToPlayer;
@override
Widget build(BuildContext context) {
return SizedBox(
height: 250,
child: ListView.builder(
scrollDirection: Axis.horizontal,
padding: const EdgeInsets.all(10),
itemCount: itemCount ?? songs.length,
itemBuilder: (context, index) => _SongCard(
songs: songs,
index: index,
passSongsToPlayer: passSongsToPlayer,
),
),
);
}
}
class _SongCard extends StatelessWidget {
const _SongCard({required this.songs, required this.index, required this.passSongsToPlayer});
final List songs;
final int index;
final bool passSongsToPlayer;
@override
Widget build(BuildContext context) {
final song = songs[index];
return InkWell(
onTap: () {
Navigator.pushNamed(context, '/player', arguments: {
'index': index,
if (passSongsToPlayer) 'songs': songs.toLocalSongs(),
});
},
child: Container(
margin: const EdgeInsets.only(right: 10, left: 6),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const SizedBox(height: 10),
ClipPath(
clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
child: CachedNetworkImage(
placeholder: (context, url) => const CircularProgressIndicator(),
errorWidget: (context, url, error) => const Icon(Icons.error),
imageUrl: song['image'],
height: 170,
width: 170,
fit: BoxFit.cover,
),
),
const Padding(padding: EdgeInsets.only(top: 2.5)),
SizedBox(
width: 165,
child: Text(song['title'],
overflow: TextOverflow.ellipsis,
style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15, color: Colors.white)),
),
Text(song['artist'],
overflow: TextOverflow.ellipsis,
style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12, color: Colors.grey)),
],
),
),
);
}
}
class _FavoriteArtistsSection extends StatelessWidget {
const _FavoriteArtistsSection();
@override
Widget build(BuildContext context) {
return SizedBox(
height: 250,
child: ListView.builder(
scrollDirection: Axis.horizontal,
itemCount: favoriteArtists.length,
itemBuilder: (context, index) {
final artist = favoriteArtists[index][0];
return InkWell(
onTap: () => Navigator.pushNamed(context, '/artist', arguments: {'index': index}),
child: Container(
margin: const EdgeInsets.only(top: 20, left: 15, bottom: 20),
child: Column(
children: [
ClipPath(
clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(200))),
child: CachedNetworkImage(
placeholder: (context, url) => const CircularProgressIndicator(),
errorWidget: (context, url, error) => const Icon(Icons.error),
imageUrl: artist['artist_img'],
height: 150,
width: 150,
fit: BoxFit.cover,
),
),
const SizedBox(height: 5),
Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Text(artist['artist'], style: const TextStyle(fontSize: 18)),
const SizedBox(width: 5),
const Icon(Icons.star, color: Color.fromARGB(255, 255, 0, 0)),
],
),
],
),
),
);
},
),
);
}
}

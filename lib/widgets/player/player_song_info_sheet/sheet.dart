part of '../player_song_info_sheet.dart';

class PlayerSongInfoSheet extends StatefulWidget {
  final LocalSong song;

  const PlayerSongInfoSheet({super.key, required this.song});

  @override
  State<PlayerSongInfoSheet> createState() => _PlayerSongInfoSheetState();
}

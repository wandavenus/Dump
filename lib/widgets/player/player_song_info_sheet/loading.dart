part of '../player_song_info_sheet.dart';

class _LoadingSongInfo extends StatelessWidget {
  const _LoadingSongInfo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 360,
      child: Center(child: CircularProgressIndicator(color: Color(0xFFF92D48))),
    );
  }
}

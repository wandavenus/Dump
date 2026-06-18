part of '../lyrics_page.dart';

class _LyricsBackgroundState extends State<_LyricsBackground> {
  @override
  Widget build(BuildContext context) {
    // BackdropFilter dihapus — ia mem-blur Scaffold hitam yang tidak memiliki
    // konten bermakna di baliknya, sehingga tidak ada efek visual nyata.
    // Efek kedalaman dijaga oleh _LyricsGradient dan overlay gelap di state.dart.
    return const Stack(
      fit: StackFit.expand,
      children: [
        _LyricsGradient(),
      ],
    );
  }
}

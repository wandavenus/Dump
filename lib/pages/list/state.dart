part of '../list.dart';

class _ListTestState extends State<ListTest> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        itemCount: _kTopPicksData.length,
        itemBuilder: (context, index) {
          return Column(
            children: [
              CachedNetworkImage(
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget:  (context, url, error) => const Icon(Icons.error),
                imageUrl: _kTopPicksData[currentIndex][0]['artist_img']!,
              ),
              CachedNetworkImage(
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget:  (context, url, error) => const Icon(Icons.error),
                imageUrl: _kTopPicksData[currentIndex][index]['image']!,
              ),
            ],
          );
        },
      ),
    );
  }
}

part of 'browse_sections.dart';

// ─── Banner carousel (local assets — tidak berubah) ───────────────────────────

class BrowseBannerCarousel extends StatelessWidget {
  const BrowseBannerCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 350,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: browseBanners.length,
        itemBuilder: (context, index) {
          final banner = browseBanners[index];
          return Container(
            width: 370,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner['t1'],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    banner['t2'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    banner['t3'],
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.normal,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipPath(
                    clipper: ShapeBorderClipper(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Image.asset(
                      banner['img'],
                      height: 720 / 3,
                      width: 1080 / 3,
                      fit: BoxFit.cover,
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

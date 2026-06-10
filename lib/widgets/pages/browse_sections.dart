import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/sample_music_data.dart';
import '../common/scrolling_page_chrome.dart';

class BrowsePageContent extends StatelessWidget {
  const BrowsePageContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: const [
          LargePageTitle(title: 'Baru'),
          HeaderDivider(),
          SizedBox(height: 12),
          BrowseBannerCarousel(),
          _BrowseSection(title: 'We Recommend'),
          _BrowseSection(title: 'New Music'),
          BrowseCategoryStrip(),
          _BrowseSection(title: 'Daily Top 100'),
        ],
      ),
    );
  }
}

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
                  Text(banner['t1'],
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                  Text(banner['t2'],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.normal, color: Colors.white),
                      overflow: TextOverflow.ellipsis),
                  Text(banner['t3'],
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.normal, color: Colors.grey)),
                  const SizedBox(height: 5),
                  ClipPath(
                    clipper: ShapeBorderClipper(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
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

class _BrowseSection extends StatelessWidget {
  const _BrowseSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 15, top: 10),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right_rounded, color: Color.fromARGB(255, 186, 186, 186)),
            ],
          ),
        ),
        const RandomSongCarousel(),
      ],
    );
  }
}

class RandomSongCarousel extends StatelessWidget {
  const RandomSongCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    final random = Random();
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        itemCount: browseSongs.length,
        itemBuilder: (context, index) {
          final song = browseSongs[random.nextInt(browseSongs.length)];
          return Container(
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
                const Padding(padding: EdgeInsets.only(top: 1)),
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
          );
        },
      ),
    );
  }
}

class BrowseCategoryStrip extends StatelessWidget {
  const BrowseCategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 145,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _GradientCategory(title: 'Music', subtitle: 'Start Singing'),
          _GradientCategory(title: 'Hits', subtitle: 'Listen Now'),
          _GradientCategory(title: 'Pop', subtitle: 'Explore More'),
        ],
      ),
    );
  }
}

class _GradientCategory extends StatelessWidget {
  const _GradientCategory({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [Color.fromARGB(255, 251, 47, 88), Color.fromARGB(255, 255, 174, 174)],
              stops: [0.4, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          margin: const EdgeInsets.only(top: 10, left: 10),
          height: 100,
          width: 200,
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 15)],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 5, left: 10),
          child: Text(subtitle, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

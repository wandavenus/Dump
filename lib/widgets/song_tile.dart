import 'package:flutter/material.dart';

class SongTile extends StatelessWidget {
  final String title;
  final String artist;
  final int index;
  final VoidCallback? onTap;

  const SongTile({
    super.key,
    required this.title,
    required this.artist,
    required this.index,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  (index + 1).toString(),
                  style: const TextStyle(fontSize: 22, color: Colors.grey),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        artist,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Icon(
              Icons.more_horiz,
              size: 25,
            ),
          ],
        ),
      ),
    );
  }
}

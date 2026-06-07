import 'package:musicplayer/widgets/common_actions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:icons_flutter/icons_flutter.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  automaticallyImplyLeading: false,
  backgroundColor: Colors.black,
  surfaceTintColor: Colors.transparent,

  actions: const [
    CommonActions(),
  ],
), 
    ),
      body: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [

Padding(
  padding: const EdgeInsets.only(
    top: 14,
    bottom: 6,
  ),

  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        "Perpustakaan",
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      Padding(
  padding: const EdgeInsets.only(top: 16),
  child: GestureDetector(
    onTap: () {},
    child: const Text(
      "Edit",
      style: TextStyle(
        color: Color(0xFFF92D48),
        fontSize: 17,
      ),
    ),
  ),
),
    ],
  ),
),

      Padding(
  padding: const EdgeInsets.only(
    left: 0,
    right: 0,
  ),
  child: const Divider(
    color: Color(0xFF38383A),
    thickness: 0.5,
    height: 0,
  ),
),
        
const SizedBox(height: 9),

     Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.music_note_list,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 11),
          Text(
            "Daftar Putar",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
    const Divider(
      color: Color(0xFF38383A),
      thickness: 0.5,
      indent: 38,
      endIndent: 1,
    ),
  ],
),                      
         
           Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.mic,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 11),
          Text(
            "Artis",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
    const Divider(
      color: Color(0xFF38383A),
      thickness: 0.5,
      indent: 38,
      endIndent: 1,
    ),
  ],
),
                
              
              Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.square_stack,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 11),
          Text(
            "Album",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
    const Divider(
      color: Color(0xFF38383A),
      thickness: 0.5,
      indent: 38,
      endIndent: 1,
    ),
  ],
),
                
              
              GestureDetector(
  onTap: () {
    Navigator.pushNamed(context, "/musiclist");
  },
  child: Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 2,
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.music_note,
              color: Color(0xFFF92D48),
              size: 28,
            ),
            SizedBox(width: 11),
            Text(
              "Lagu",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      const Divider(
        color: Color(0xFF38383A),
        thickness: 0.5,
        indent: 38,
        endIndent: 1,
      ),
    ],
  ),
),
        Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.tv,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 11),
          Text(
            "TV & Film",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
    const Divider(
      color: Color(0xFF38383A),
      thickness: 0.5,
      indent: 38,
      endIndent: 1,
    ),
  ],
),         
 ],
          ),
        ),
      ),
    );
  }
}
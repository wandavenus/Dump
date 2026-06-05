
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:icons_flutter/icons_flutter.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {

double _scrollOffset = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
       automaticallyImplyLeading: false,
backgroundColor: Colors.black,
surfaceTintColor: Colors.transparent, 
    
actions: [
  IconButton(
    onPressed: () {},
    icon: const Icon(
      Icons.cast_outlined,
      color: Color(0xFFF92D48),
      size: 24,
    ),
  ),
  PopupMenuButton(
    icon: const Icon(
      Icons.more_vert,
      color: Color(0xFFF92D48),
      size: 24,
    ),
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: 'settings',
        child: Text('Pengaturan'),
      ),
    ],
  ),
],

       flexibleSpace: Stack(
  children: [

     
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
    top: 8,
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
      GestureDetector(
        onTap: () {},
        child: const Text(
          "Edit",
          style: TextStyle(
            color: Color(0xFFF92D48),
            fontSize: 17,
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
             Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.music_note_list,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 9),
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
      indent: 37,
      endIndent: 5,
    ),
  ],
),                      
         
           Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.mic,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 9),
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
      indent: 37,
      endIndent: 5,
    ),
  ],
),
                
              
              Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.square_stack,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 9),
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
      indent: 37,
      endIndent: 5,
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
          vertical: 6,
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.music_note,
              color: Color(0xFFF92D48),
              size: 28,
            ),
            SizedBox(width: 9),
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
        indent: 37,
        endIndent: 5,
      ),
    ],
  ),
),
        Column(
  children: [
    Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.tv,
            color: Color(0xFFF92D48),
            size: 28,
          ),
          SizedBox(width: 9),
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
      indent: 37,
      endIndent: 5,
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
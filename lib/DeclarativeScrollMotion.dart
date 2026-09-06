import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DeclarativeScrollMotion extends StatelessWidget {
  final ScrollController _controller = ScrollController();

  DeclarativeScrollMotion({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: _controller,
      children: [
        // This container animates based on scroll distance (0px to 300px)
        Container(
              height: 250,
              color: Colors.deepPurple,
              alignment: Alignment.center,
              child: const Text(
                'Scroll to morph me',
                style: TextStyle(color: Colors.white, fontSize: 22),
              ),
            )
            .animate(adapter: ScrollAdapter(_controller, begin: 0, end: 300))
            .fade(begin: 1.0, end: 0.2)
            .scale(begin: const Offset(1, 1), end: const Offset(0.8, 0.8))
            .blur(begin: const Offset(0, 0), end: const Offset(8, 8)),

        ...List.generate(30, (i) => ListTile(title: Text('Row $i'))),
      ],
    );
  }
}

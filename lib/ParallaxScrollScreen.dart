import 'package:flutter/material.dart';

import 'ParallaxHeaderDelegate.dart';

class ParallaxScrollScreen extends StatelessWidget {
  const ParallaxScrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: ParallaxHeaderDelegate(
              maxHeight: 320.0,
              minHeight: MediaQuery.of(context).padding.top + kToolbarHeight,
              title: 'Alpine Pass',
              imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            sliver: SliverList.builder(
              itemCount: 20,
              itemBuilder: (context, index) {
                return Card(
                  color: const Color(0xFF1E1E1E),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      'Destination Stop #${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Altitude: ${1200 + (index * 85)}m',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white38,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

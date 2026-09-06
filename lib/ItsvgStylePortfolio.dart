import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ItsvgStylePortfolio extends StatefulWidget {
  const ItsvgStylePortfolio({super.key});

  @override
  State<ItsvgStylePortfolio> createState() => _ItsvgStylePortfolioState();
}

class _ItsvgStylePortfolioState extends State<ItsvgStylePortfolio> {
  final ScrollController _mainController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: CustomScrollView(
        controller: _mainController,
        slivers: [
          // Hero Section
          SliverToBoxAdapter(
            child: Container(
              height: MediaQuery.of(context).size.height,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                        "VISHWA GAURAV",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -2,
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .slideY(begin: 0.2, end: 0),
                  const Text(
                    "Creative Developer & Designer",
                    style: TextStyle(color: Colors.white70, fontSize: 18),
                  ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.5, end: 0),
                  const SizedBox(height: 50),
                  const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white24,
                        size: 40,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .moveY(
                        begin: 0,
                        end: 10,
                        duration: 1.seconds,
                        curve: Curves.easeInOut,
                      )
                      .fadeIn(),
                ],
              ),
            ),
          ),

          // Infinite Marquee Section
          SliverToBoxAdapter(
            child: Container(
              height: 120,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const MarqueeWidget(
                texts: [
                  "FLUTTER",
                  "DART",
                  "FIREBASE",
                  "ANIMATIONS",
                  "UI/UX",
                  "RIVE",
                  "LOTTIE",
                ],
              ),
            ),
          ),

          // About Section with Reveal
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 150,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                        "Principles",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      .animate(
                        adapter: ScrollAdapter(
                          _mainController,
                          begin: 400,
                          end: 700,
                        ),
                      )
                      .fadeIn()
                      .slideX(begin: -0.1, end: 0),
                  const SizedBox(height: 30),
                  const Text(
                        "I build digital products with a focus on performance, responsiveness, and delightful user experiences. Every pixel matters, every interaction tells a story.",
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 24,
                          height: 1.5,
                        ),
                      )
                      .animate(
                        adapter: ScrollAdapter(
                          _mainController,
                          begin: 500,
                          end: 900,
                        ),
                      )
                      .fadeIn()
                      .slideY(begin: 0.1, end: 0),
                ],
              ),
            ),
          ),

          // Horizontal Pinned Projects Section
          SliverPersistentHeader(
            pinned: true,
            delegate: HorizontalPinnedDelegate(
              headerHeight: 600,
              scrollDistance: 2000,
              child: const ProjectsHorizontalList(),
            ),
          ),

          // Footer / Content after Horizontal Section
          SliverToBoxAdapter(child: FooterSection(controller: _mainController)),
        ],
      ),
    );
  }
}

class FooterSection extends StatefulWidget {
  final ScrollController controller;
  const FooterSection({super.key, required this.controller});

  @override
  State<FooterSection> createState() => _FooterSectionState();
}

class _FooterSectionState extends State<FooterSection> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateProgress);
  }

  void _updateProgress() {
    if (!mounted || !widget.controller.hasClients) return;

    // The footer appears at the very end of the scroll.
    // We calculate progress based on how close we are to the bottom.
    final maxScroll = widget.controller.position.maxScrollExtent;
    final currentScroll = widget.controller.offset;

    // Trigger in the last 400 pixels of the scroll
    final double p = ((currentScroll - (maxScroll - 400)) / 300).clamp(
      0.0,
      1.0,
    );

    if (p != _progress) {
      setState(() {
        _progress = p;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateProgress);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 600,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0F0F0F),
            Colors.deepPurple.withOpacity(0.05),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 0.8 + (0.2 * _progress),
            child: Opacity(
              opacity: _progress,
              child: const Text(
                "LET'S CONNECT",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Opacity(
            opacity: _progress,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - _progress)),
              child: Column(
                children: [
                  const Text(
                    "Available for new opportunities",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 16),
                  ),
                  const SizedBox(height: 40),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 20,
                      ),
                    ),
                    child: const Text("SAY HELLO"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarqueeWidget extends StatefulWidget {
  final List<String> texts;
  const MarqueeWidget({super.key, required this.texts});

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    _scrollController
        .animateTo(
          maxScroll,
          duration: Duration(seconds: widget.texts.length * 3),
          curve: Curves.linear,
        )
        .then((_) {
          if (mounted) {
            _scrollController.jumpTo(0);
            _startScrolling();
          }
        });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Triple the list for seamless loop
    final items = [...widget.texts, ...widget.texts, ...widget.texts];
    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Center(
            child: Text(
              items[index],
              style: TextStyle(
                color: Colors.white.withOpacity(0.05),
                fontSize: 64,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}

class HorizontalPinnedDelegate extends SliverPersistentHeaderDelegate {
  final double headerHeight;
  final double scrollDistance;
  final Widget child;

  HorizontalPinnedDelegate({
    required this.headerHeight,
    required this.scrollDistance,
    required this.child,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // progress goes from 0.0 to 1.0 over the scrollDistance
    final double progress = (shrinkOffset / scrollDistance).clamp(0.0, 1.0);
    // Calculate the current extent to match what SliverPersistentHeader expects
    final double currentExtent = max(minExtent, maxExtent - shrinkOffset);

    return Container(
      color: const Color(0xFF0F0F0F),
      height: currentExtent,
      child: Stack(
        children: [
          // We keep the actual content pinned at the top of the sliver's area
          // with a fixed height equal to headerHeight
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 24,
                  top: 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PROJECTS",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          fontSize: 12,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        height: 2,
                        width: 40,
                        color: Colors.white.withOpacity(0.2),
                        margin: const EdgeInsets.only(top: 8),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Transform.translate(
                    // Move content horizontally based on scroll progress
                    offset: Offset(-progress * 1800, 0),
                    child: child,
                  ),
                ),
                // Scroll Progress Indicator at bottom
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 200,
                      height: 2,
                      color: Colors.white10,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 200 * progress,
                            child: Container(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => headerHeight + scrollDistance;

  @override
  double get minExtent => headerHeight;

  @override
  bool shouldRebuild(covariant HorizontalPinnedDelegate oldDelegate) => true;
}

class ProjectsHorizontalList extends StatelessWidget {
  const ProjectsHorizontalList({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 200), // Initial padding
        ...List.generate(5, (index) {
          return Container(
            width: 500,
            height: 400,
            margin: const EdgeInsets.only(right: 100),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "0${index + 1}",
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  "Project Title ${index + 1}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "A showcase of modern mobile development using Flutter and advanced animations.",
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const Spacer(),
                const Row(
                  children: [
                    Text(
                      "VIEW CASE STUDY",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

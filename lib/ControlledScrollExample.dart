import 'package:flutter/material.dart';

class ControlledScrollExample extends StatefulWidget {
  const ControlledScrollExample({super.key});

  @override
  State<ControlledScrollExample> createState() =>
      _ControlledScrollExampleState();
}

class _ControlledScrollExampleState extends State<ControlledScrollExample> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _scrollToBottom,
        child: const Icon(Icons.arrow_downward),
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: 40,
        itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class StaffTab extends StatelessWidget {
  const StaffTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
      ),
      body: const Center(
        child: Text('Staff Tab'),
      ),
    );
  }
}

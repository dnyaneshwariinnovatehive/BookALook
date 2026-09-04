import 'package:flutter/material.dart';

class AppointmentsTab extends StatelessWidget {
  const AppointmentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Appointments'),
      ),
      body: const Center(
        child: Text('Appointments Tab'),
      ),
    );
  }
}

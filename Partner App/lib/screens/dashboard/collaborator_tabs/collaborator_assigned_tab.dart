import 'package:flutter/material.dart';

class CollaboratorAssignedTab extends StatelessWidget {
  const CollaboratorAssignedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.assignment_ind_outlined,
            size: 80,
            color: Colors.orange,
          ),
          SizedBox(height: 24),
          Text(
            'Assigned Salons & Alerts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Manage salons assigned to you by the SuperAdmin from the public enquiry form, and receive subscription alerts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

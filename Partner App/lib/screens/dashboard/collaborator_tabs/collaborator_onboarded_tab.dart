import 'package:flutter/material.dart';

class CollaboratorOnboardedTab extends StatelessWidget {
  const CollaboratorOnboardedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.fact_check_outlined,
            size: 80,
            color: Colors.green,
          ),
          SizedBox(height: 24),
          Text(
            'My Onboarded Salons',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'A list of all salons you have onboarded, tracking their Pending, Approved, or Rejected status.',
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

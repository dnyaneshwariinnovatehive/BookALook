import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('Running...');
  // Simulating the JSON parsing we get from the backend
  String jsonString = '''
{
    "appointments": [
        {
            "id": "a2acd498-0cdc-4588-acb0-b6206cc848fd",
            "salon_id": "a2a7bd03-2393-48f4-bf8c-f1e55079bfee",
            "customer_id": "a2a7d3b0-da1e-4b93-8bdc-b3415701026a",
            "appointed_provider_id": "a2a80e44-2ade-406b-981a-f448d7711e70",
            "serving_provider_id": null,
            "booking_source": "online",
            "appointment_date": "2026-09-05",
            "start_time": "10:00:00",
            "end_time": "10:00:00",
            "status": "scheduled",
            "payment_option": "advance_only",
            "total_amount": 688,
            "advance_amount": 137.6,
            "balance_amount": 550.4,
            "final_billed_amount": null,
            "walk_in_customer_name": null,
            "walk_in_customer_phone": null,
            "qr_token_hash": "cbc7966c6d924e549884b8658a025f688ebdd4ceaa9e5b63e5c0b94e7364c541",
            "customer": {
                "id": "a2a7d3b0-da1e-4b93-8bdc-b3415701026a",
                "name": "test uesr"
            },
            "services": [],
            "service_additions": []
        }
    ]
}
  ''';

  final decoded = jsonDecode(jsonString)['appointments'];
  final apt = decoded[0];
  
  bool isWalkIn = apt['booking_source'] == 'walk_in';
  String customerName = isWalkIn ? (apt['walk_in_customer_name'] ?? 'Walk-In Customer') : (apt['customer'] != null ? apt['customer']['name'] : 'Unknown Customer');
  
  List services = apt['services'] ?? [];
  String serviceNames = services.map((s) => s['service']?['name'] ?? 'Service').join(', ');
  if (serviceNames.isEmpty) serviceNames = 'General Service';
  
  int duration = services.fold(0, (sum, s) => (sum as int) + (s['duration_minutes_at_booking'] as int? ?? 0));
  
  print('Duration: \$duration');
  print('Done parsing');
}

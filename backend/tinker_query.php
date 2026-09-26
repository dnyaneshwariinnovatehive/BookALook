<?php
$appointment = App\Models\Appointment::with('customer')
    ->whereHas('customer', function($q) { 
        $q->where('email', 'like', '%test%')->orWhere('name', 'like', '%test%'); 
    })
    ->orWhere('walk_in_customer_name', 'like', '%test%')
    ->orderBy('created_at', 'desc')
    ->first();
    
echo json_encode($appointment, JSON_PRETTY_PRINT);

<?php
$user = \App\Models\User::where('phone', '9112002049')->first();
$salon = \App\Models\Salon::where('admin_id', $user->id)->first();
$sub = $salon->currentSubscription()->with('plan')->first();
dump($sub ? $sub->toArray() : 'No current sub returned');

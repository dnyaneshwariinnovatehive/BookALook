<?php
$user = \App\Models\User::where('phone', '9112002049')->first();
dump($user ? $user->toArray() : 'User not found');
if ($user) {
    $salon = \App\Models\Salon::where('admin_id', $user->id)->first();
    dump($salon ? $salon->toArray() : 'Salon not found');
    if ($salon) {
        $subs = $salon->subscriptions()->get();
        dump($subs->toArray());
    }
}

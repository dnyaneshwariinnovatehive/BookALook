<?php
use App\Models\Salon;
use Illuminate\Support\Facades\DB;

$ids = ['a2a7ae92-057f-4559-9276-3a4b6e4e707d','a2a7bd03-2393-48f4-bf8c-f1e55079bfee'];

foreach (Salon::whereIn('id',$ids)->get() as $s) {
    echo "\n================ {$s->name} ({$s->id}) status={$s->status}\n";

    $sub = DB::table('salon_subscriptions')->where('salon_id',$s->id)->orderByDesc('created_at')->first();
    echo "subscription: ".($sub ? "{$sub->status} billing={$sub->billing_type} {$sub->start_date}..{$sub->end_date} plan={$sub->plan_id}" : 'NONE')."\n";

    echo "working hours: ";
    foreach (DB::table('salon_working_hours')->where('salon_id',$s->id)->orderBy('day_of_week')->get() as $h) {
        echo $h->day_of_week.($h->is_closed?'(closed)':"({$h->open_time}-{$h->close_time}) ");
    }
    echo "\n";

    echo "providers:\n";
    foreach (DB::table('service_providers as sp')->join('users as u','u.id','=','sp.user_id')->where('sp.salon_id',$s->id)->get(['sp.id','u.name','u.phone','sp.is_active','sp.base_salary','sp.commission_percentage']) as $p) {
        $svc = DB::table('provider_services')->where('provider_id',$p->id)->count();
        $wh  = DB::table('provider_working_hours')->where('provider_id',$p->id)->count();
        echo "  - {$p->name} ({$p->phone}) active={$p->is_active} salary={$p->base_salary} comm={$p->commission_percentage} services={$svc} hours={$wh} id={$p->id}\n";
    }

    echo "services:\n";
    foreach (DB::table('services as s')->join('service_templates as t','t.id','=','s.template_id')->where('s.salon_id',$s->id)->get(['s.id','t.name','s.price','s.advance_percentage','s.is_active','t.estimated_duration_minutes']) as $sv) {
        echo "  - {$sv->name} Rs{$sv->price} adv{$sv->advance_percentage}% dur={$sv->estimated_duration_minutes} active={$sv->is_active} id={$sv->id}\n";
    }

    echo "combos:\n";
    foreach (DB::table('combos')->where('salon_id',$s->id)->get() as $c) {
        $n = DB::table('combo_services')->where('combo_id',$c->id)->count();
        echo "  - {$c->name} active={$c->is_active} services={$n} id={$c->id}\n";
    }

    echo "appointments by status: ";
    foreach (DB::table('appointments')->where('salon_id',$s->id)->select('status',DB::raw('count(*) c'))->groupBy('status')->get() as $r) echo "{$r->status}={$r->c} ";
    echo "\n";

    $w = DB::table('salon_wallets')->where('salon_id',$s->id)->first();
    echo "wallet: ".($w? "balance={$w->coin_balance} earned={$w->total_earned} redeemed={$w->total_redeemed}" : 'NONE')."\n";
    echo "wallet txns: ".DB::table('wallet_transactions')->where('salon_id',$s->id)->count()."\n";
    echo "payouts: ".DB::table('salon_payouts')->where('salon_id',$s->id)->count()."\n";
    echo "salary payouts: ".DB::table('salary_payouts')->where('salon_id',$s->id)->count()."\n";
    echo "leaves: ".DB::table('provider_leaves')->whereIn('provider_id', DB::table('service_providers')->where('salon_id',$s->id)->pluck('id'))->count()."\n";
}

echo "\n=== platform ===\n";
echo "plans:\n";
foreach (DB::table('subscription_plans')->get() as $p) {
    echo "  - {$p->name} type={$p->billing_type} price={$p->price} commission={$p->commission_percentage} active={$p->is_active} id={$p->id}\n";
}
echo "wallet schemes: ".DB::table('wallet_schemes')->count()." tiers: ".DB::table('wallet_scheme_tiers')->count()."\n";
foreach (DB::table('wallet_schemes')->get() as $sc) { echo "  - {$sc->name} active={$sc->is_active} id={$sc->id}\n"; }
echo "customers: ".DB::table('users')->where('role','customer')->count()."\n";
foreach (DB::table('users')->where('role','customer')->limit(10)->get(['id','name','phone']) as $c) echo "  - {$c->name} {$c->phone} {$c->id}\n";
echo "service_templates: ".DB::table('service_templates')->count()."\n";
echo "policy settings:\n";
foreach (DB::table('platform_policy_settings')->get() as $ps) echo "  - {$ps->setting_key} = {$ps->setting_value}\n";

{{--
    The invoice a customer sees.

    Self-contained on purpose: no external stylesheet, no fonts, no scripts
    beyond the print button, because the whole point is that this renders
    identically in a WebView, in a browser, and on paper. The accent colour is
    the only thing that varies, and the controller has already reduced it to a
    hex triple or thrown it away.

    Everything the customer reads goes through {{ }} so a service name, a salon
    name or a SuperAdmin-typed term can never inject markup here.
--}}
@php
    $accent = $settings['invoice_accent_color'];
    $currency = fn ($n) => '₹' . number_format((float) $n, 2);
    $slot = \Carbon\Carbon::parse($invoice->appointment_date . ' ' . $invoice->start_time)
        ->format('D, d M Y');
    $time = \Carbon\Carbon::parse($invoice->appointment_date . ' ' . $invoice->start_time)
        ->format('g:i A');
    $endTime = \Carbon\Carbon::parse($invoice->appointment_date . ' ' . $invoice->end_time)
        ->format('g:i A');
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>Invoice {{ $invoice->invoice_number }}</title>
    <style>
        :root { --accent: {{ $accent }}; }
        * { box-sizing: border-box; }
        body {
            margin: 0; padding: 24px;
            background: #f4f2ee; color: #1c1a17;
            font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        }
        .sheet {
            max-width: 820px; margin: 0 auto; background: #fff;
            border-radius: 14px; box-shadow: 0 1px 3px rgba(0,0,0,.10);
            padding: 40px;
        }
        .bar { display: flex; justify-content: flex-end; margin-bottom: 16px; }
        button {
            font: inherit; cursor: pointer; padding: 9px 18px;
            border: 0; border-radius: 9px; background: var(--accent); color: #fff;
        }
        .head { display: flex; justify-content: space-between; gap: 28px; align-items: flex-start;
                padding-bottom: 22px; border-bottom: 2px solid var(--accent); }
        .brand { display: flex; gap: 14px; align-items: flex-start; }
        .brand img { max-height: 58px; max-width: 190px; object-fit: contain; }
        .brand h1 { margin: 0; font-size: 23px; letter-spacing: -.4px; }
        .brand .lines { margin-top: 5px; color: #6b655d; font-size: 13px; }
        .brand .lines div { margin-top: 1px; }
        .meta { text-align: right; flex-shrink: 0; }
        .doc { font-size: 11px; letter-spacing: 1.4px; text-transform: uppercase; color: #8a837a; }
        .num { font-size: 17px; font-weight: 650; margin-top: 3px; }
        .meta .when { color: #6b655d; font-size: 13px; margin-top: 3px; }
        .grid { display: flex; gap: 28px; flex-wrap: wrap; padding: 22px 0; }
        .col { flex: 1 1 210px; min-width: 0; }
        .label { font-size: 10.5px; letter-spacing: 1.2px; text-transform: uppercase;
                 color: #8a837a; margin-bottom: 5px; }
        .col p { margin: 0; }
        .col .muted { color: #6b655d; font-size: 13.5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 6px; }
        thead th {
            text-align: left; font-size: 10.5px; letter-spacing: 1.1px; text-transform: uppercase;
            color: #8a837a; font-weight: 600; padding: 9px 10px;
            border-bottom: 1.5px solid var(--accent);
        }
        tbody td { padding: 12px 10px; border-bottom: 1px solid #ece8e1; vertical-align: top; }
        .right { text-align: right; white-space: nowrap; }
        .name { font-weight: 550; }
        .sub { color: #8a837a; font-size: 12.5px; margin-top: 2px; }
        .tag {
            display: inline-block; margin-left: 7px; padding: 1px 7px; border-radius: 5px;
            /* Plain tint first, so an older Android WebView without color-mix
               still gets a readable chip rather than an invisible one. */
            background: #f1ede6;
            background: color-mix(in srgb, var(--accent) 13%, transparent);
            color: var(--accent); font-size: 10.5px; font-weight: 600;
            letter-spacing: .4px; text-transform: uppercase; vertical-align: 1.5px;
        }
        .totals { display: flex; justify-content: flex-end; margin-top: 20px; }
        .totals table { width: 300px; }
        .totals td { padding: 7px 10px; }
        .totals tr:last-child td {
            border-top: 2px solid var(--accent); font-weight: 700; font-size: 17px; padding-top: 11px;
        }
        .totals .due td { color: var(--accent); font-weight: 650; }
        .paid { color: #2f7d4f; }
        .foot { margin-top: 30px; padding-top: 18px; border-top: 1px solid #ece8e1; }
        .terms { color: #6b655d; font-size: 12.5px; white-space: pre-line; }
        .note { margin-top: 14px; color: #6b655d; font-size: 13.5px; }

        /* Paper. The screen furniture is dropped and the sheet is allowed to
           use the whole page, because a browser printing this should produce
           something a salon would be happy to staple to a file. */
        @media print {
            @page { size: A4; margin: 14mm; }
            body { background: #fff; padding: 0; }
            .sheet { box-shadow: none; border-radius: 0; padding: 0; max-width: none; }
            .bar { display: none; }
            thead { display: table-header-group; }
            tr { break-inside: avoid; }
            .foot { break-inside: avoid; }
        }
    </style>
</head>
<body>
<div class="sheet">

    <div class="bar">
        <button type="button" onclick="window.print()">Print / Save as PDF</button>
    </div>

    <header class="head">
        <div class="brand">
            @if ($settings['invoice_show_logo'] && $settings['invoice_logo_url'])
                <img src="{{ $settings['invoice_logo_url'] }}" alt="{{ $settings['invoice_business_name'] }}">
            @endif
            <div>
                <h1>{{ $settings['invoice_business_name'] }}</h1>
                @if ($settings['invoice_show_business_address'] && $settings['invoice_business_address'])
                    <div class="lines">{{ $settings['invoice_business_address'] }}</div>
                @endif
                @if ($settings['invoice_business_phone'] || $settings['invoice_business_email'])
                    <div class="lines">
                        @if ($settings['invoice_business_phone'])<div>{{ $settings['invoice_business_phone'] }}</div>@endif
                        @if ($settings['invoice_business_email'])<div>{{ $settings['invoice_business_email'] }}</div>@endif
                    </div>
                @endif
                @if ($settings['invoice_show_tax_id'] && $settings['invoice_tax_id'] && $settings['invoice_tax_id_label'])
                    <div class="lines"><strong>{{ $settings['invoice_tax_id_label'] }}:</strong> {{ $settings['invoice_tax_id'] }}</div>
                @endif
            </div>
        </div>
        <div class="meta">
            <div class="doc">Invoice</div>
            <div class="num">{{ $invoice->invoice_number }}</div>
            <div class="when">Issued {{ $invoice->issued_at->format('d M Y') }}</div>
        </div>
    </header>

    <section class="grid">
        <div class="col">
            <div class="label">Billed to</div>
            <p class="name">{{ $invoice->bill_to_name ?: 'Customer' }}</p>
            @if ($invoice->bill_to_phone)<p class="muted">{{ $invoice->bill_to_phone }}</p>@endif
            @if ($invoice->bill_to_email)<p class="muted">{{ $invoice->bill_to_email }}</p>@endif
        </div>
        <div class="col">
            <div class="label">Appointment</div>
            <p class="name">{{ $invoice->salon_name ?: 'Salon' }}</p>
            @if ($settings['invoice_show_provider'] && $invoice->provider_name)
                <p class="muted">{{ $invoice->provider_name }}</p>
            @endif
            <p class="muted">{{ $slot }} &middot; {{ $time }}&ndash;{{ $endTime }}</p>
        </div>
    </section>

    <table>
        <thead>
            <tr>
                <th>Service</th>
                @if ($settings['invoice_show_duration_column'])<th class="right">Duration</th>@endif
                <th class="right">Amount</th>
            </tr>
        </thead>
        <tbody>
            @foreach ($invoice->line_items as $line)
                <tr>
                    <td>
                        <span class="name">{{ $line['name'] }}</span>
                        @if (($line['kind'] ?? '') === 'package')<span class="tag">Package</span>@endif
                        @if ($settings['invoice_show_provider'] && ! empty($line['provider_name']))
                            <div class="sub">{{ $line['provider_name'] }}</div>
                        @endif
                    </td>
                    @if ($settings['invoice_show_duration_column'])
                        <td class="right">{{ $line['duration_minutes'] }} min</td>
                    @endif
                    <td class="right">{{ $currency($line['price']) }}</td>
                </tr>
            @endforeach
        </tbody>
    </table>

    <div class="totals">
        <table>
            <tr>
                <td>Total</td>
                <td class="right">{{ $currency($invoice->total) }}</td>
            </tr>
            <tr class="paid">
                <td>Advance paid</td>
                <td class="right">&minus; {{ $currency($invoice->advance_paid) }}</td>
            </tr>
            @if ($settings['invoice_show_balance_due'])
                <tr class="due">
                    <td>Balance due at salon</td>
                    <td class="right">{{ $currency($invoice->balance_due) }}</td>
                </tr>
            @endif
        </table>
    </div>

    <footer class="foot">
        @if ($settings['invoice_show_terms'] && $settings['invoice_terms'])
            <div class="terms">{{ $settings['invoice_terms'] }}</div>
        @endif
        @if ($settings['invoice_footer_note'])
            <div class="note">{{ $settings['invoice_footer_note'] }}</div>
        @endif
    </footer>

</div>
</body>
</html>

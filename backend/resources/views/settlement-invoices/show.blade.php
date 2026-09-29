{{--
    The settlement statement a salon owner sees.

    The mirror image of invoices/show.blade.php, and deliberately built from the
    same parts: one shared letterhead, one accent colour, one set of terms. If
    the two documents looked like two different companies, an owner matching a
    statement against a customer invoice would have no way of telling which was
    which.

    Self-contained on purpose: no external stylesheet, no fonts, no scripts
    beyond the print button, because the whole point is that this renders
    identically in a browser and on paper. The accent colour is the only thing
    that varies, and the controller has already reduced it to a hex triple or
    thrown it away.

    Everything the owner reads goes through {{ }} so a salon name or a
    SuperAdmin-typed term can never inject markup here.
--}}
@php
    $accent = $settings['invoice_accent_color'];
    $currency = fn ($n) => '₹' . number_format((float) $n, 2);

    // Deductions are already negative on the line, so they are printed with a
    // minus rather than a bracket. An owner reading a statement has to see at a
    // glance which way each row moves the total.
    $signed = fn (float $n) => $n < 0 ? '&minus; ' . $currency(abs($n)) : $currency($n);
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ $settings['settlement_invoice_document_title'] ?: 'Settlement Invoice' }} {{ $invoice->invoice_number }}</title>
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
        .deduction { color: #a8443a; }
        .totals { display: flex; justify-content: flex-end; margin-top: 20px; }
        .totals table { width: 320px; }
        .totals td { padding: 7px 10px; }
        .totals tr:last-child td {
            border-top: 2px solid var(--accent); font-weight: 700; font-size: 17px; padding-top: 11px;
        }
        .totals .net td { color: var(--accent); font-weight: 650; }
        .paid { color: #2f7d4f; }
        .foot { margin-top: 30px; padding-top: 18px; border-top: 1px solid #ece8e1; }
        .terms { color: #6b655d; font-size: 12.5px; white-space: pre-line; }
        .note { margin-top: 14px; color: #6b655d; font-size: 13.5px; }

        /* Paper. The screen furniture is dropped and the sheet is allowed to
           use the whole page, because a browser printing this should produce
           something an owner would be happy to staple to a file. */
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
            <div class="doc">{{ $settings['settlement_invoice_document_title'] ?: 'Settlement Invoice' }}</div>
            <div class="num">{{ $invoice->invoice_number }}</div>
            <div class="when">Issued {{ $invoice->issued_at->format('d M Y') }}</div>
        </div>
    </header>

    <section class="grid">
        <div class="col">
            <div class="label">Settled with</div>
            <p class="name">{{ $invoice->salon_name ?: 'Salon' }}</p>
            @if ($invoice->salon_address)<p class="muted">{{ $invoice->salon_address }}</p>@endif
            @if ($invoice->salon_phone)<p class="muted">{{ $invoice->salon_phone }}</p>@endif
            @if ($invoice->owner_name)<p class="muted">{{ $invoice->owner_name }}</p>@endif
        </div>
        <div class="col">
            <div class="label">Period</div>
            <p class="name">{{ $invoice->cycle_label }}</p>
            <p class="muted">
                {{ $invoice->cycle_start_date->format('d M Y') }} &ndash; {{ $invoice->cycle_end_date->format('d M Y') }}
            </p>
            <p class="muted">
                {{ \App\Support\BillingModel::label($invoice->billing_type) }}
                <span class="tag">{{ ucfirst($invoice->cycle_type) }}ly settled</span>
            </p>
            @if ($settings['settlement_invoice_show_appointments_count'] && $invoice->appointments_count)
                <p class="muted">{{ $invoice->appointments_count }} completed appointment{{ $invoice->appointments_count === 1 ? '' : 's' }}</p>
            @endif
        </div>
    </section>

    <table>
        <thead>
            <tr>
                <th>How this was worked out</th>
                <th class="right">Amount</th>
            </tr>
        </thead>
        <tbody>
            @foreach ($invoice->line_items as $line)
                <tr>
                    <td>
                        <span class="name">{{ $line['name'] }}</span>
                        @if (! empty($line['detail']))
                            <div class="sub">{{ $line['detail'] }}</div>
                        @endif
                    </td>
                    <td class="right {{ ((float) $line['amount']) < 0 ? 'deduction' : '' }}">{!! $signed((float) $line['amount']) !!}</td>
                </tr>
            @endforeach
        </tbody>
    </table>

    <div class="totals">
        <table>
            @if ($settings['settlement_invoice_show_billed_revenue'])
                <tr>
                    <td>Total billed by you</td>
                    <td class="right">{{ $currency($invoice->appointment_revenue) }}</td>
                </tr>
            @endif
            @if ($invoice->commission_deducted > 0)
                <tr class="deduction">
                    <td>Commission at {{ rtrim(rtrim(number_format($invoice->commission_percentage, 2), '0'), '.') }}%</td>
                    <td class="right">&minus; {{ $currency($invoice->commission_deducted) }}</td>
                </tr>
            @endif
            <tr class="net">
                <td>{{ $invoice->paid_at ? 'Paid to you' : 'Net payable' }}</td>
                <td class="right">{{ $currency($invoice->net_amount) }}</td>
            </tr>
        </table>
    </div>

    <footer class="foot">
        @if ($invoice->paid_at)
            <div class="paid">Paid on {{ $invoice->paid_at->format('d M Y') }}@if ($invoice->distribution_reference) &middot; Reference {{ $invoice->distribution_reference }}@endif</div>
        @endif
        @if ($settings['invoice_show_terms'] && $settings['invoice_terms'])
            <div class="terms">{{ $settings['invoice_terms'] }}</div>
        @endif
        @if ($settings['settlement_invoice_footer_note'])
            <div class="note">{{ $settings['settlement_invoice_footer_note'] }}</div>
        @endif
    </footer>

</div>
</body>
</html>

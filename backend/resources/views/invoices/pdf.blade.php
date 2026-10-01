{{--
    The invoice as a PDF, for sending to a customer on WhatsApp.

    A sibling of invoices/show.blade.php, not a reuse of it. That view is built
    for a browser and leans on flexbox, CSS custom properties and color-mix();
    dompdf implements none of those, so pointing it at the screen view produces a
    document with a missing accent colour and a header laid out in one column.
    This one is tables and inline styles only.

    Everything the customer reads still goes through {{ }}, so a service name or a
    SuperAdmin-typed term cannot inject markup here either. The accent colour has
    already been reduced to a hex triple by the controller.
--}}
@php
    $accent = $settings['invoice_accent_color'];
    $currency = fn ($n) => '₹' . number_format((float) $n, 2);
    $slot = $invoice->appointmentDateLabel();
    $time = $invoice->startTimeLabel();
    $endTime = $invoice->endTimeLabel();
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Invoice {{ $invoice->invoice_number }}</title>
    <style>
        /* No custom properties and no calc(): dompdf resolves both only
           partially, and a rule that loses its colour silently loses the
           document's whole hierarchy. Every colour is written out. */
        @page { margin: 26px 30px; }

        body {
            margin: 0; padding: 0;
            color: #1c1a17;
            font-family: DejaVu Sans, sans-serif;
            font-size: 10.5px;
            line-height: 1.45;
        }
        table { width: 100%; border-collapse: collapse; }
        td, th { vertical-align: top; }

        .brand-name   { font-size: 15px; font-weight: bold; padding: 0 0 3px 0; }
        .brand-lines  { color: #6b655d; font-size: 9.5px; }
        .head-rule    { border-bottom: 2px solid {{ $accent }}; }

        .label {
            font-size: 8.5px; letter-spacing: 1px; text-transform: uppercase;
            color: #8a837a; font-weight: bold; padding: 0 0 3px 0;
        }
        .doc-type {
            font-size: 8.5px; letter-spacing: 1.4px; text-transform: uppercase;
            color: #8a837a; text-align: right;
        }
        .doc-number { font-size: 13px; font-weight: bold; text-align: right; padding: 2px 0 0 0; }
        .doc-when   { color: #6b655d; font-size: 9.5px; text-align: right; padding-top: 2px; }

        .section-gap td { padding-top: 18px; }
        .name    { font-weight: bold; }
        .muted   { color: #6b655d; font-size: 9.5px; padding-top: 1px; }

        thead th {
            text-align: left; font-size: 8.5px; letter-spacing: 1px;
            text-transform: uppercase; color: #8a837a; font-weight: bold;
            padding: 8px 8px; border-bottom: 1.5px solid {{ $accent }};
        }
        thead th.right { text-align: right; }
        tbody td { padding: 9px 8px; border-bottom: 1px solid #ece8e1; }
        tbody td.right { text-align: right; white-space: nowrap; }
        .sub { color: #8a837a; font-size: 9px; padding-top: 2px; }
        .tag {
            font-size: 8px; font-weight: bold; letter-spacing: .4px;
            text-transform: uppercase; color: {{ $accent }};
        }

        .totals td { padding: 5px 8px; }
        .totals tr.grand td {
            border-top: 2px solid {{ $accent }}; font-weight: bold;
            font-size: 13px; padding-top: 9px;
        }
        .totals tr.grand td.right { text-align: right; }
        .totals td.label-right { text-align: right; }
        .paid  { color: #2f7d4f; }
        .due   { color: {{ $accent }}; font-weight: bold; }

        .foot       { border-top: 1px solid #ece8e1; }
        .foot td    { padding-top: 14px; }
        .terms      { color: #6b655d; font-size: 9px; }
        .foot-note  { color: #6b655d; font-size: 9.5px; padding-top: 9px; }
    </style>
</head>
<body>

{{-- Letterhead and document number share one row, so the accent rule spans the
     full width of the page rather than stopping at the text. --}}
<table class="head-rule">
    <tr>
        <td style="width: 62%">
            @if ($settings['invoice_show_logo'] && $settings['invoice_logo_url'])
                <img src="{{ $settings['invoice_logo_url'] }}" alt="" style="max-height: 46px; max-width: 170px;">
            @endif
            <div class="brand-name">{{ $settings['invoice_business_name'] }}</div>
            @if ($settings['invoice_show_business_address'] && $settings['invoice_business_address'])
                <div class="brand-lines">{{ $settings['invoice_business_address'] }}</div>
            @endif
            @if ($settings['invoice_business_phone'] || $settings['invoice_business_email'])
                <div class="brand-lines">
                    @if ($settings['invoice_business_phone'])<div>{{ $settings['invoice_business_phone'] }}</div>@endif
                    @if ($settings['invoice_business_email'])<div>{{ $settings['invoice_business_email'] }}</div>@endif
                </div>
            @endif
            @if ($settings['invoice_show_tax_id'] && $settings['invoice_tax_id'] && $settings['invoice_tax_id_label'])
                <div class="brand-lines"><strong>{{ $settings['invoice_tax_id_label'] }}:</strong> {{ $settings['invoice_tax_id'] }}</div>
            @endif
        </td>
        <td style="width: 38%">
            <div class="doc-type">Invoice</div>
            <div class="doc-number">{{ $invoice->invoice_number }}</div>
            <div class="doc-when">Issued {{ $invoice->issued_at->format('d M Y') }}</div>
        </td>
    </tr>
</table>

{{-- Billed-to and appointment sit side by side. --}}
<table class="section-gap">
    <tr>
        <td style="width: 50%; padding-right: 20px;">
            <div class="label">Billed to</div>
            <div class="name">{{ $invoice->bill_to_name ?: 'Customer' }}</div>
            @if ($invoice->bill_to_phone)<div class="muted">{{ $invoice->bill_to_phone }}</div>@endif
            @if ($invoice->bill_to_email)<div class="muted">{{ $invoice->bill_to_email }}</div>@endif
        </td>
        <td style="width: 50%;">
            <div class="label">Appointment</div>
            <div class="name">{{ $invoice->salon_name ?: 'Salon' }}</div>
            @if ($settings['invoice_show_provider'] && $invoice->provider_name)
                <div class="muted">{{ $invoice->provider_name }}</div>
            @endif
            <div class="muted">{{ $slot }} &middot; {{ $time }}&ndash;{{ $endTime }}</div>
        </td>
    </tr>
</table>

<table class="section-gap">
    <thead>
        <tr>
            <th>Service</th>
            @if ($settings['invoice_show_duration_column'])<th class="right" style="width: 90px">Duration</th>@endif
            <th class="right" style="width: 110px">Amount</th>
        </tr>
    </thead>
    <tbody>
        @foreach ($invoice->line_items as $line)
            <tr>
                <td>
                    {{ $line['name'] }}
                    @if (($line['kind'] ?? '') === 'package') <span class="tag">[Package]</span>@endif
                    @if ($settings['invoice_show_provider'] && ! empty($line['provider_name']))
                        <div class="sub">{{ $line['provider_name'] }}</div>
                    @endif
                </td>
                @if ($settings['invoice_show_duration_column'])
                    <td class="right">{{ ! empty($line['duration_minutes']) ? intval($line['duration_minutes']).' min' : '—' }}</td>
                @endif
                <td class="right">{{ $currency($line['price']) }}</td>
            </tr>
        @endforeach
    </tbody>
</table>

{{-- Totals are right-aligned through a spacer column rather than a flex row,
     because dompdf has no flexbox to justify with. --}}
<table class="section-gap">
    <tr>
        <td style="width: 55%"></td>
        <td class="totals" style="width: 45%">
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
        </td>
    </tr>
</table>

<table class="foot section-gap">
    <tr>
        <td>
            @if ($settings['invoice_show_terms'] && $settings['invoice_terms'])
                <div class="terms">{!! nl2br(e($settings['invoice_terms'])) !!}</div>
            @endif
            @if ($settings['invoice_footer_note'])
                <div class="foot-note">{{ $settings['invoice_footer_note'] }}</div>
            @endif
        </td>
    </tr>
</table>

</body>
</html>
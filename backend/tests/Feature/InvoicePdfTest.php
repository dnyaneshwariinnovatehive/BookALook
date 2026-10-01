<?php

namespace Tests\Feature;

use App\Models\Appointment;
use App\Models\Invoice;
use App\Models\InvoiceSetting;
use App\Models\Salon;
use App\Models\ServiceProvider;
use App\Models\User;
use App\Services\InvoicePdfService;
use App\Support\InvoiceTemplate;
use Barryvdh\DomPDF\Facade\Pdf;
use CloudinaryLabs\CloudinaryLaravel\Facades\Cloudinary;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\Support\FakesCloudinaryUpload;
use Tests\TestCase;

/**
 * The invoice as a PDF, which is the copy a customer receives over WhatsApp.
 *
 * The invoice already had a web page and tests. What is new here is that it can
 * be rendered, published somewhere a third party can fetch it, and referenced
 * stably enough to be sent twice.
 *
 * Three properties are being defended:
 *
 *  1. It renders at all, and the figures survive the trip. The PDF view is a
 *     separate Blade from the screen one, so "it looks right on the website" says
 *     nothing about it — dompdf implements none of the flexbox the screen view is
 *     built on.
 *  2. The URL is stable. A message that is retried must point at the same file;
 *     a second render would leave the customer holding a second copy of the same
 *     receipt under a different name.
 *  3. A PDF that cannot be produced does not fail a booking. The invoice is
 *     already issued and the customer already has it in the app by this point.
 */
class InvoicePdfTest extends TestCase
{
    use DatabaseTransactions;
    use FakesCloudinaryUpload;

    public function test_it_renders_an_invoice_to_a_pdf(): void
    {
        $invoice = $this->issuedInvoice();

        $output = Pdf::loadView('invoices.pdf', [
            'invoice' => $invoice,
            'settings' => InvoiceTemplate::sanitise($invoice->template ?? []),
        ])->output();

        $this->assertStringStartsWith('%PDF-', $output);
        $this->assertGreaterThan(1000, strlen($output), 'a blank page is not an invoice');
    }

    public function test_it_uploads_the_pdf_and_records_the_url(): void
    {
        $cloud = $this->fakeCloudinaryUpload();
        $invoice = $this->issuedInvoice();

        $url = app(InvoicePdfService::class)->urlFor($invoice);

        $this->assertNotNull($url, 'the PDF should have been produced');
        $this->assertSame($url, $invoice->refresh()->pdf_url);

        // Asserted against the public ID actually sent, rather than by picking
        // the path back out of the URL: what matters is that the URL handed to
        // AISensy names the file that is actually there.
        $this->assertStringStartsWith('invoices/', $cloud->options['public_id']);
        $this->assertStringEndsWith('.pdf', $url, 'WhatsApp needs a URL it can recognise as a PDF');
    }

    public function test_the_upload_names_the_pdf_so_cloudinary_accepts_it(): void
    {
        // Found in production. The disk adapter classifies application/pdf as a
        // *raw* resource, and the SDK only infers a filename from a local path. A
        // streamed raw upload therefore reaches Cloudinary as a nameless multipart
        // part, and Cloudinary falls back to reading the body as a *source URL*,
        // rejecting the request with "Invalid request parameters". Passing the
        // filename explicitly is what turns the body back into a file.
        //
        // This is why screenshots upload fine and invoices do not: they go up as
        // images, where Cloudinary sniffs the content rather than trusting a name.
        $cloud = $this->fakeCloudinaryUpload();
        $invoice = $this->issuedInvoice();
        $this->assertNotNull(app(InvoicePdfService::class)->urlFor($invoice));

        $this->assertSame(
            $invoice->invoice_number.'.pdf',
            $cloud->options['filename'],
            'a raw stream without an explicit filename is read as a source URL and rejected'
        );
        $this->assertSame('raw', $cloud->options['resource_type'], 'a PDF is a raw resource, not an image');

        // A raw resource has no format for Cloudinary to append: its extension is
        // part of the public ID. Without it the delivered URL is extensionless
        // and WhatsApp cannot tell the document is a PDF.
        $this->assertStringEndsWith('.pdf', $cloud->options['public_id']);
        $this->assertArrayNotHasKey('format', $cloud->options, 'format is for images and video, not raw files');
    }

    public function test_publish_reports_why_the_pdf_could_not_be_produced(): void
    {
        // urlFor() swallows the failure, which is right for the in-app invoice,
        // but the WhatsApp send has to be able to say *why* it has no document.
        // Before publish() existed the only visible error was AISensy's "Media
        // URL Missing", which names the wrong system entirely.
        Cloudinary::shouldReceive('uploadApi')->andThrow(new \RuntimeException('Invalid request parameters'));

        $invoice = $this->issuedInvoice();

        try {
            app(InvoicePdfService::class)->publish($invoice);
            $this->fail('publish() should throw when the upload is rejected');
        } catch (\RuntimeException $e) {
            $this->assertSame('Invalid request parameters', $e->getMessage());
        }

        $this->assertNull($invoice->refresh()->pdf_url, 'a failed upload must stay retryable');
    }

    public function test_the_url_comes_from_the_upload_response_rather_than_being_guessed(): void
    {
        // Storage::url() would string-build the public URL from the path. The
        // upload response carries the real one, so that is what gets stored —
        // otherwise a CDN prefix or a signature would be silently dropped and
        // AISensy would be handed a URL that 404s.
        $cloud = $this->fakeCloudinaryUpload();
        $invoice = $this->issuedInvoice();

        $url = app(InvoicePdfService::class)->urlFor($invoice);

        $this->assertNotNull($url);
        $this->assertSame(
            'https://res.cloudinary.com/demo/raw/upload/'.$cloud->options['public_id'],
            $url
        );
    }

    public function test_a_cloudinary_failure_leaves_the_invoice_without_a_pdf_url(): void
    {
        // An invoice is already issued and already visible in the app by the time
        // anyone asks for a PDF of it, so an upload failure is something to log
        // and report — never a reason to fail the booking that caused it, and never
        // a reason to record a URL that does not resolve.
        Cloudinary::shouldReceive('uploadApi')->andThrow(new \RuntimeException('Invalid request parameters'));

        $invoice = $this->issuedInvoice();

        $this->assertNull(app(InvoicePdfService::class)->urlFor($invoice));
        $this->assertNull($invoice->refresh()->pdf_url);
    }

    public function test_the_pdf_reaches_cloudinary_as_a_stream_rather_than_a_string(): void
    {
        // Found in production. The first version of this passed a string, because
        // that is what Storage::put() is documented to take and what every other
        // disk in the app wants. Cloudinary's upload API reads a bare string as a
        // *local file path* and calls fopen() on it. A PDF is binary and full of
        // null bytes, so fopen() refuses it and the upload throws "Argument #1
        // ($filename) must not contain any null bytes" — an error that names
        // neither Cloudinary nor PDF generation, so it read as a corrupt file
        // rather than a contract mismatch. Because the catch in urlFor() swallows
        // it into a log line, the customer simply never received a message.
        $cloud = $this->fakeCloudinaryUpload();

        $invoice = $this->issuedInvoice();

        $this->assertNotNull(
            app(InvoicePdfService::class)->urlFor($invoice),
            'the PDF should have been produced'
        );

        $this->assertIsResource(
            $cloud->asset,
            'Cloudinary must receive a stream; a string is treated as a local file path and fopen() is called on the PDF itself'
        );

        // The stream has to hold the PDF itself, not a path to it.
        $this->assertStringStartsWith('%PDF', $cloud->body);
        $this->assertStringContainsString('%EOF', $cloud->body, 'a truncated write would still start with %PDF');
    }

    public function test_the_url_is_reused_rather_than_re_rendered(): void
    {
        $cloud = $this->fakeCloudinaryUpload();

        $invoice = $this->issuedInvoice();
        $service = app(InvoicePdfService::class);

        $first = $service->urlFor($invoice);
        $this->assertNotNull($first);

        // A second call must not mint a second document. If it did, a retried
        // WhatsApp send would hand the customer two identical receipts.
        $this->assertSame($first, $service->urlFor($invoice));

        // Counted on the upload API rather than by listing a fake disk: the second
        // call has to be answered from the cached URL, so Cloudinary must never be
        // reached again.
        $this->assertSame(
            1,
            $cloud->uploads,
            'a second render would leave the customer with two identical receipts at different URLs'
        );
    }

    public function test_a_logo_url_carrying_control_characters_is_dropped(): void
    {
        // Found in production: a SuperAdmin-authored logo URL containing a null
        // byte reached dompdf, which passes it to fopen()/curl. Both refuse such a
        // path by throwing, and dompdf does not catch that, so the render died —
        // and because the PDF is the WhatsApp attachment, the customer message
        // died with it. The provider reported the send as "Media URL Missing",
        // which points at AISensy rather than at the logo, so this is easy to
        // misread as a messaging problem.
        //
        // Asserted on the sanitiser rather than through a render: the failure is
        // that the value escapes at all, and a render-level test would pass or
        // fail on the machine's GD build instead of on the behaviour.
        foreach ([
            "https://cdn.example.com/logo.jpg\0",
            "https://cdn.example.com/lo\0go.jpg",
            "https://cdn.example.com/logo.jpg\0.php",
            "https://cdn.example.com/logo.jpg\n",
            "https://cdn.example.com/logo.jpg\r\n",
            "https://cdn.example.com/logo.jpg\t",
        ] as $hostile) {
            $sanitised = InvoiceTemplate::sanitise(['invoice_logo_url' => $hostile]);

            $this->assertSame('', $sanitised['invoice_logo_url'], 'A logo URL containing a control character must not survive sanitisation.');
        }

        // The scheme check is still a prefix check, so make sure tightening it did
        // not turn into something that rejects real URLs.
        $legitimate = 'https://res.cloudinary.com/demo/image/upload/sample.jpg';
        $this->assertSame(
            $legitimate,
            InvoiceTemplate::sanitise(['invoice_logo_url' => $legitimate])['invoice_logo_url']
        );
    }

    public function test_an_invoice_with_a_hostile_logo_url_still_renders(): void
    {
        $invoice = $this->issuedInvoice();
        $invoice->template = array_merge($invoice->template ?? [], [
            'invoice_show_logo' => true,
            'invoice_logo_url' => "https://cdn.example.com/logo.jpg\0",
        ]);

        $output = Pdf::loadView('invoices.pdf', [
            'invoice' => $invoice,
            'settings' => InvoiceTemplate::sanitise($invoice->template),
        ])->setOptions([
            'isRemoteEnabled' => true,
            'isPhpEnabled' => false,
            'isJavascriptEnabled' => false,
            'isHtml5ParserEnabled' => false,
        ])->output();

        $this->assertStringStartsWith('%PDF', $output);
    }

    public function test_an_upload_that_reports_no_url_does_not_throw(): void
    {
        // A 200 from Cloudinary carrying neither secure_url nor public_id is the
        // shape of a misconfigured account — wrong API secret, wrong cloud, or a
        // signed-upload profile with no delivery. Storing an empty pdf_url would
        // be worse than storing none: urlFor() short-circuits on a filled value,
        // so the invoice would be cached as "already done" and never retried.
        $this->fakeCloudinaryUpload('');

        $invoice = $this->issuedInvoice();

        // The invoice is already issued and already visible in the app, so failing
        // to produce a PDF is a thing to log and report — never a reason to fail
        // the booking that caused it.
        $this->assertNull(app(InvoicePdfService::class)->urlFor($invoice));
        $this->assertNull($invoice->refresh()->pdf_url);
    }

    // ------------------------------------------------------------- fixtures

    /**
     * An issued invoice, built directly.
     *
     * Deliberately not booked through the API. The whole booking flow needs a
     * seeded salon, staff with services, and a day with a free slot, and when any
     * of that is missing this file skips itself — which is how a broken invoice
     * layout can sit unnoticed on a database nobody seeded. The PDF only needs an
     * invoice, so the invoice is what gets built.
     */
    private function issuedInvoice(): Invoice
    {
        $unique = substr(bin2hex(random_bytes(6)), 0, 10);

        $admin = User::create([
            'name' => "Pdf Admin {$unique}",
            'phone' => '9'.substr((string) crc32("pdfadmin{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'admin',
        ]);

        $customer = User::create([
            'name' => "Pdf Customer {$unique}",
            'phone' => '9'.substr((string) crc32("pdfcust{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'customer',
        ]);

        $salon = Salon::create([
            'admin_id' => $admin->id,
            'name' => "Glow Studio {$unique}",
            'slug' => "glow-studio-{$unique}",
            'address' => '12 FC Road, Pune 411001',
            'phone_num' => '9876543210',
            'submitted_by' => $admin->id,
            'status' => 'active',
        ]);

        $staffUser = User::create([
            'name' => "Pdf Staff {$unique}",
            'phone' => '8'.substr((string) crc32("pdfstaff{$unique}"), 0, 9),
            'password_hash' => 'x',
            'role' => 'service_provider',
        ]);

        $staff = ServiceProvider::create([
            'user_id' => $staffUser->id,
            'salon_id' => $salon->id,
        ]);

        $appointment = Appointment::create([
            'customer_id' => $customer->id,
            'salon_id' => $salon->id,
            'appointed_provider_id' => $staff->id,
            'appointment_date' => now()->addDay()->toDateString(),
            'start_time' => '16:30',
            'end_time' => '17:15',
            'status' => 'confirmed',
            'total_amount' => 1250,
            'advance_amount' => 500,
            'balance_amount' => 750,
        ]);

        return Invoice::create([
            'appointment_id' => $appointment->id,
            'invoice_number' => 'BAL-'.strtoupper($unique),
            'issued_at' => now(),
            'bill_to_name' => $customer->name,
            'bill_to_phone' => $customer->phone,
            'salon_name' => $salon->name,
            'salon_address' => $salon->address,
            'provider_name' => $staffUser->name,
            'appointment_date' => $appointment->appointment_date,
            'start_time' => $appointment->start_time,
            'end_time' => $appointment->end_time,
            'line_items' => [
                ['name' => 'Haircut', 'kind' => 'service', 'price' => 500, 'duration_minutes' => 45, 'provider_name' => 'Riya'],
                ['name' => 'Blow Dry', 'kind' => 'service', 'price' => 750, 'duration_minutes' => 45, 'provider_name' => 'Riya'],
            ],
            'subtotal' => 1250,
            'advance_paid' => 500,
            'balance_due' => 750,
            'total' => 1250,
            'template' => InvoiceSetting::typed(),
        ]);
    }

    public function test_the_date_and_time_survive_both_a_write_and_a_read(): void
    {
        $invoice = $this->issuedInvoice();

        // The same labels from a row that has just been written, and from one that
        // has been read back out of the database. These differ: the attribute is
        // either `2026-10-02` or `2026-10-02 00:00:00` depending on which, and
        // reading a date out of the pair used to throw on the freshly written one,
        // taking the whole PDF with it.
        $fresh = $invoice->fresh();

        $this->assertSame($invoice->appointmentDateLabel(), $fresh->appointmentDateLabel());
        $this->assertSame('4:30 PM', $fresh->startTimeLabel());
        $this->assertSame('5:15 PM', $fresh->endTimeLabel());

        // And the date is a real formatted date, not a datetime with a time glued
        // onto the end of it.
        $this->assertMatchesRegularExpression('/^\w{3}, \d{2} \w{3} \d{4}$/', $fresh->appointmentDateLabel());
    }
}

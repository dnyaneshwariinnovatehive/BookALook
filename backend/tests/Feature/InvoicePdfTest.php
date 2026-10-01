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
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Storage;
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
        Storage::fake('cloudinary');

        $invoice = $this->issuedInvoice();

        $url = app(InvoicePdfService::class)->urlFor($invoice);

        $this->assertNotNull($url, 'the PDF should have been produced');
        $this->assertSame($url, $invoice->refresh()->pdf_url);

        // Asserted against the disk's own listing rather than by picking the path
        // back out of the URL: what matters is that the URL handed to AISensy
        // names the file that is actually there.
        $files = Storage::disk('cloudinary')->allFiles();

        $this->assertCount(1, $files);
        $this->assertStringStartsWith('invoices/', $files[0]);
        $this->assertStringEndsWith('/'.basename($files[0]), $url);
    }

    public function test_the_pdf_reaches_cloudinary_as_a_stream_rather_than_a_string(): void
    {
        // Found in production. Storage::fake() swaps in a local disk, and a local
        // disk is happy to be handed the PDF as a string of bytes, so the faked
        // disk proves nothing about the real Cloudinary adapter.
        //
        // The adapter forwards a bare string into Cloudinary's upload API, which
        // reads a string as a *local file path* and calls fopen() on it. A PDF is
        // binary and full of null bytes, so fopen() refuses it and the upload
        // throws "Argument #1 ($filename) must not contain any null bytes" — which
        // names neither Cloudinary nor PDF generation, and so read as a corrupt
        // file rather than a contract mismatch. Because the catch in urlFor()
        // swallows it into a log line, the customer simply never received a
        // message.
        //
        // This drives a real Laravel FilesystemAdapter over a recording Flysystem
        // adapter, so what is asserted is the contract between the two libraries
        // rather than the behaviour of a substitute disk. The recorded value is
        // the last thing that crossed into the adapter — the same position the
        // real Cloudinary adapter occupies.
        $recorded = new class implements \League\Flysystem\FilesystemAdapter
        {
            public mixed $received = null;

            public function fileExists(string $path): bool
            {
                return true;
            }

            public function directoryExists(string $path): bool
            {
                return true;
            }

            public function write(string $path, string $contents, \League\Flysystem\Config $config): void
            {
                $this->received = ['type' => 'string', 'value' => $contents];
            }

            public function writeStream(string $path, $contents, \League\Flysystem\Config $config): void
            {
                // Read it here rather than after the call returns: the caller owns
                // the handle and closes it, which is correct of it and is exactly
                // why a stream is a one-shot thing to test against.
                $this->received = ['type' => 'stream', 'value' => $contents];
                $this->body = (string) stream_get_contents($contents);
            }

            public function read(string $path): string
            {
                return '';
            }

            public function readStream(string $path)
            {
                return null;
            }

            public function delete(string $path): void {}

            public function deleteDirectory(string $path): void {}

            public function createDirectory(string $path, \League\Flysystem\Config $config): void {}

            public function setVisibility(string $path, string $visibility): void {}

            public function listContents(string $path, bool $deep): iterable
            {
                return [];
            }

            public function move(string $source, string $destination, \League\Flysystem\Config $config): void {}

            public function copy(string $source, string $destination, \League\Flysystem\Config $config): void {}

            /** The real adapter answers this; url() falls through to it. */
            public function getUrl(string $path): string
            {
                return 'https://res.cloudinary.com/demo/image/upload/'.$path;
            }

            public function visibility(string $path): \League\Flysystem\FileAttributes
            {
                return new \League\Flysystem\FileAttributes($path);
            }

            public function mimeType(string $path): \League\Flysystem\FileAttributes
            {
                return new \League\Flysystem\FileAttributes($path);
            }

            public function lastModified(string $path): \League\Flysystem\FileAttributes
            {
                return new \League\Flysystem\FileAttributes($path);
            }

            public function fileSize(string $path): \League\Flysystem\FileAttributes
            {
                return new \League\Flysystem\FileAttributes($path);
            }
        };

        Storage::extend('recording', fn () => new \Illuminate\Filesystem\FilesystemAdapter(
            new \League\Flysystem\Filesystem($recorded),
            $recorded
        ));

        config([
            'filesystems.disks.cloudinary' => [
                'driver' => 'recording',
                'url' => 'https://res.cloudinary.com/demo/image/upload',
            ],
        ]);

        $invoice = $this->issuedInvoice();

        $this->assertNotNull(
            app(InvoicePdfService::class)->urlFor($invoice),
            'the PDF should have been produced'
        );

        $this->assertIsArray($recorded->received, 'nothing reached the upload adapter');
        $this->assertSame(
            'stream',
            $recorded->received['type'],
            'Cloudinary must receive a stream; a string is treated as a local file path and fopen() is called on the PDF itself'
        );
        $this->assertIsResource($recorded->received['value']);

        // The stream has to hold the PDF itself, not a path to it. Read inside the
        // adapter, because the caller closes the handle once it is done.
        $this->assertStringStartsWith('%PDF', $recorded->body);
        $this->assertStringContainsString('%EOF', $recorded->body, 'a truncated write would still start with %PDF');
    }

    public function test_the_stored_pdf_is_byte_identical_to_the_rendered_one(): void
    {
        // Guards the seam this fix introduced. The bytes now travel through a
        // stream rather than being handed over directly, and a stream can be read
        // once — so a rewrite that forgets to rewind, or that reads the handle
        // after the upload consumed it, would store an empty file that still
        // satisfies a "does it start with %PDF" check on the wrong side of the
        // read.
        Storage::fake('cloudinary');

        $invoice = $this->issuedInvoice();

        $url = app(InvoicePdfService::class)->urlFor($invoice);
        $this->assertNotNull($url);

        $files = Storage::disk('cloudinary')->allFiles();
        $this->assertCount(1, $files);

        $stored = Storage::disk('cloudinary')->get($files[0]);

        $this->assertStringStartsWith('%PDF', $stored, 'the stored file must be the PDF itself');
        $this->assertStringContainsString('%EOF', $stored, 'the stored file must be complete, not a truncated stream');
        $this->assertGreaterThan(
            1000,
            strlen($stored),
            'a PDF this small means the stream was consumed rather than copied'
        );
    }

    public function test_the_url_is_reused_rather_than_re_rendered(): void
    {
        Storage::fake('cloudinary');

        $invoice = $this->issuedInvoice();
        $service = app(InvoicePdfService::class);

        $first = $service->urlFor($invoice);
        $this->assertNotNull($first);

        // A second call must not mint a second document. If it did, a retried
        // WhatsApp send would hand the customer two identical receipts.
        $this->assertSame($first, $service->urlFor($invoice));

        $this->assertCount(
            1,
            collect(Storage::disk('cloudinary')->allFiles())->filter(fn ($f) => str_contains($f, '.pdf'))
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

    public function test_a_broken_disk_does_not_throw(): void
    {
        // The shape of a staging box where CLOUDINARY_URL has been filled in with
        // something that cannot be written to. Pointed *inside* a file rather than
        // at a nonexistent path, because "a directory that does not exist" is
        // quietly creatable on some platforms and not others, and this test is not
        // about filesystems.
        config([
            'filesystems.disks.cloudinary' => [
                'driver' => 'local',
                'root' => storage_path('logs/laravel.log/impossible'),
            ],
        ]);

        $invoice = $this->issuedInvoice();

        // The invoice is already issued and already visible in the app, so failing
        // to produce a PDF is a thing to log and report — never a reason to fail
        // the booking that caused it.
        $this->assertNull(app(InvoicePdfService::class)->urlFor($invoice));
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
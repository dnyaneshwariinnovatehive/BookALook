<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Staff Dues</title>
    <style>
        body { font-family: sans-serif; color: #333; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <h2>Staff Pending Dues Summary</h2>
    <p><strong>Salon:</strong> {{ $salon->name }}</p>
    <p><strong>Generated On:</strong> {{ now()->format('d M Y, h:i A') }}</p>
    
    <table>
        <tr>
            <th>Provider Name</th>
            <th>Salary Month</th>
            <th>Amount Due</th>
        </tr>
        @forelse($salaries as $s)
        <tr>
            <td>{{ $s->provider->user->name ?? 'Unknown' }}</td>
            <td>{{ $s->salary_month->format('M Y') }}</td>
            <td>Rs {{ number_format($s->total_payable, 2) }}</td>
        </tr>
        @empty
        <tr>
            <td colspan="3" style="text-align: center;">No pending dues found for any staff.</td>
        </tr>
        @endforelse
    </table>
</body>
</html>

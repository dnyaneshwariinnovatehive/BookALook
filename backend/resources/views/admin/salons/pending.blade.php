@extends('layouts.admin')

@section('title', 'Salon Approval Queue')

@section('content')
<div class="bg-white rounded-lg shadow-sm border border-gray-200">
    <div class="p-6 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-800">Pending Salons</h2>
        <p class="text-sm text-gray-500 mt-1">Review and approve or reject newly submitted salons.</p>
    </div>

    <div class="overflow-x-auto">
        <table class="w-full text-left text-sm text-gray-600">
            <thead class="bg-gray-50 text-gray-700 uppercase text-xs font-semibold border-b border-gray-200">
                <tr>
                    <th class="px-6 py-4">Salon Name</th>
                    <th class="px-6 py-4">City</th>
                    <th class="px-6 py-4">Owner/Admin</th>
                    <th class="px-6 py-4">Submitted At</th>
                    <th class="px-6 py-4 text-right">Action</th>
                </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
                @forelse($salons as $salon)
                    <tr class="hover:bg-gray-50">
                        <td class="px-6 py-4 font-medium text-gray-900">{{ $salon->name }}</td>
                        <td class="px-6 py-4">{{ $salon->city ? $salon->city->name : 'N/A' }}</td>
                        <td class="px-6 py-4">{{ $salon->admin ? $salon->admin->name : 'N/A' }}</td>
                        <td class="px-6 py-4">{{ $salon->created_at->format('M d, Y h:i A') }}</td>
                        <td class="px-6 py-4 text-right">
                            <a href="{{ route('admin.salons.show', $salon->id) }}" class="inline-flex items-center justify-center px-4 py-2 bg-indigo-600 text-white rounded text-sm font-medium hover:bg-indigo-700 transition">
                                Review
                            </a>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="5" class="px-6 py-8 text-center text-gray-500">
                            No salons pending approval.
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>
    </div>
</div>
@endsection

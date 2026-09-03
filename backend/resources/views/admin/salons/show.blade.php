@extends('layouts.admin')

@section('title', 'Review Salon')

@section('content')
<div class="mb-4">
    <a href="{{ route('admin.salons.pending') }}" class="text-indigo-600 hover:text-indigo-800 flex items-center gap-2">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"></path></svg>
        Back to Queue
    </a>
</div>

<div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
    <div class="flex items-center justify-between border-b border-gray-200 pb-4 mb-6">
        <div>
            <h2 class="text-2xl font-bold text-gray-900">{{ $salon->name }}</h2>
            <p class="text-sm text-gray-500 mt-1">Submitted on {{ $salon->created_at->format('M d, Y h:i A') }}</p>
        </div>
        <div>
            <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-yellow-100 text-yellow-800">
                Pending Approval
            </span>
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mb-8">
        <!-- Salon Details -->
        <div>
            <h3 class="text-lg font-semibold text-gray-800 border-b border-gray-100 pb-2 mb-4">Salon Information</h3>
            <div class="space-y-3">
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Slug</span>
                    <span class="text-gray-900">{{ $salon->slug }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">City</span>
                    <span class="text-gray-900">{{ $salon->city ? $salon->city->name : 'N/A' }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Address</span>
                    <span class="text-gray-900">{{ $salon->address }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Pincode</span>
                    <span class="text-gray-900">{{ $salon->pincode }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Gender Focus</span>
                    <span class="text-gray-900">{{ $salon->gender_focus ?? 'N/A' }}</span>
                </div>
                @if($salon->description)
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Description</span>
                    <p class="text-gray-900 mt-1 text-sm bg-gray-50 p-3 rounded">{{ $salon->description }}</p>
                </div>
                @endif
            </div>
        </div>

        <!-- Owner Details -->
        <div>
            <h3 class="text-lg font-semibold text-gray-800 border-b border-gray-100 pb-2 mb-4">Owner / Admin Information</h3>
            @if($salon->admin)
            <div class="space-y-3">
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Full Name</span>
                    <span class="text-gray-900">{{ $salon->admin->name }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Phone</span>
                    <span class="text-gray-900">{{ $salon->admin->phone }}</span>
                </div>
                <div>
                    <span class="block text-xs font-medium text-gray-500 uppercase">Email</span>
                    <span class="text-gray-900">{{ $salon->admin->email ?? 'N/A' }}</span>
                </div>
            </div>
            @else
            <p class="text-gray-500">No admin information found.</p>
            @endif
        </div>
    </div>

    <!-- Actions -->
    <div class="border-t border-gray-200 pt-6 flex gap-4">
        <!-- Approve Form -->
        <form action="{{ route('admin.salons.approve', $salon->id) }}" method="POST">
            @csrf
            <button type="submit" class="px-6 py-2 bg-green-600 text-white rounded font-medium hover:bg-green-700 transition" onclick="return confirm('Are you sure you want to approve this salon?');">
                Approve Salon
            </button>
        </form>
        
        <!-- Reject Button (Trigger Modal) -->
        <button type="button" class="px-6 py-2 bg-red-600 text-white rounded font-medium hover:bg-red-700 transition" onclick="document.getElementById('rejectModal').classList.remove('hidden')">
            Reject Salon
        </button>
    </div>
</div>

<!-- Reject Modal -->
<div id="rejectModal" class="fixed inset-0 bg-gray-900 bg-opacity-50 hidden flex items-center justify-center z-50">
    <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4 shadow-xl">
        <h3 class="text-lg font-bold text-gray-900 mb-4">Reject Salon</h3>
        
        <form action="{{ route('admin.salons.reject', $salon->id) }}" method="POST">
            @csrf
            <div class="mb-4">
                <label for="rejection_reason" class="block text-sm font-medium text-gray-700 mb-1">Reason for Rejection *</label>
                <textarea name="rejection_reason" id="rejection_reason" rows="4" class="w-full border-gray-300 rounded-md shadow-sm p-2 border focus:border-indigo-500 focus:ring-indigo-500" required placeholder="Tell the owner why their salon was rejected..."></textarea>
            </div>
            
            <div class="flex justify-end gap-3 mt-6">
                <button type="button" class="px-4 py-2 text-gray-600 hover:text-gray-800 font-medium" onclick="document.getElementById('rejectModal').classList.add('hidden')">Cancel</button>
                <button type="submit" class="px-4 py-2 bg-red-600 text-white rounded font-medium hover:bg-red-700">Submit Rejection</button>
            </div>
        </form>
    </div>
</div>
@endsection

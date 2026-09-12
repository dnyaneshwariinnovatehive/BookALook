<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\Customer\CustomerAuthController;
use App\Http\Controllers\Api\SuperAdmin\SuperAdminAuthController;

Route::prefix('customer')->group(function () {
    Route::post('/auth/send-otp', [CustomerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [CustomerAuthController::class, 'verifyOtp']);
    Route::post('/auth/complete-profile', [CustomerAuthController::class, 'completeProfile']);
    
    // Public routes
    Route::get('/banners', [\App\Http\Controllers\Api\Customer\BannerController::class, 'index']);
    Route::get('/categories', [\App\Http\Controllers\Api\Customer\CategoryController::class, 'index']);
    Route::get('/salons', [\App\Http\Controllers\Api\Customer\SalonController::class, 'index']);
    Route::get('/salons/{id}', [\App\Http\Controllers\Api\Customer\SalonController::class, 'show']);

    // Protected customer routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [CustomerAuthController::class, 'logout']);
        Route::get('/profile', [CustomerAuthController::class, 'profile']);
        // Switching market happens from the home screen, not the profile form.
        Route::put('/profile/city', [CustomerAuthController::class, 'updateCity']);
        
        // Favourites
        Route::get('/favorites', [\App\Http\Controllers\Api\Customer\FavouriteController::class, 'index']);
        Route::post('/salons/{salon_id}/favorite', [\App\Http\Controllers\Api\Customer\FavouriteController::class, 'toggle']);
        
        // Cart Routes
        Route::get('/cart', [\App\Http\Controllers\Api\Customer\CartController::class, 'getGlobalCart']);
        Route::delete('/cart', [\App\Http\Controllers\Api\Customer\CartController::class, 'clearGlobalCart']);
        Route::get('/salons/{salon_id}/cart', [\App\Http\Controllers\Api\Customer\CartController::class, 'getCart']);
        Route::post('/salons/{salon_id}/cart/items', [\App\Http\Controllers\Api\Customer\CartController::class, 'addItem']);
        Route::delete('/cart/items/{item_id}', [\App\Http\Controllers\Api\Customer\CartController::class, 'removeItem']);
        Route::delete('/salons/{salon_id}/cart', [\App\Http\Controllers\Api\Customer\CartController::class, 'clearCart']);

        // Appointment Routes
        Route::get('/salons/{salon_id}/providers', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'getProviders']);
        Route::get('/salons/{salon_id}/availability', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'getAvailableSlots']);
        Route::post('/salons/{salon_id}/appointments/book', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'book']);
        Route::get('/appointments', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'index']);
        Route::get('/appointments/{id}', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'show']);
        Route::post('/appointments/{id}/cancel', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'cancel']);
        Route::get('/appointments/{id}/reschedule-options', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'rescheduleOptions']);
        Route::post('/appointments/{id}/reschedule', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'reschedule']);
        Route::post('/appointments/{id}/generate-qr', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'generateQr']);

        // Booking payment (Razorpay). Appointment advances only — salon
        // subscriptions are paid by transfer and verified from a screenshot.
        Route::post('/appointments/{id}/payment/confirm', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'confirmPayment']);
        Route::post('/appointments/{id}/payment/demo-pay', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'demoPay']);
        Route::post('/appointments/{id}/payment/abandon', [\App\Http\Controllers\Api\Customer\AppointmentController::class, 'abandonPayment']);

        // In-app notification inbox
        Route::get('/notifications', [\App\Http\Controllers\Api\Customer\NotificationController::class, 'index']);
        Route::post('/notifications/read-all', [\App\Http\Controllers\Api\Customer\NotificationController::class, 'markAllRead']);
        Route::post('/notifications/{id}/read', [\App\Http\Controllers\Api\Customer\NotificationController::class, 'markRead']);
    });
});

// Public global routes
Route::get('/cities', [\App\Http\Controllers\Api\CityController::class, 'index']);
Route::get('/cities/nearest', [\App\Http\Controllers\Api\CityController::class, 'nearest']);
Route::post('/enquiries', [\App\Http\Controllers\Api\PublicEnquiryController::class, 'store']);

// What a scanned salon QR code resolves to. Open to anyone: the person holding
// the phone has no account yet, which is the whole point of the poster.
Route::get('/public/salons/{slug}', [\App\Http\Controllers\Api\PublicSalonController::class, 'show']);
Route::get('/public/app-links', [\App\Http\Controllers\Api\PublicSalonController::class, 'appLinks']);

Route::prefix('superadmin')->group(function () {
    Route::post('/auth/login', [SuperAdminAuthController::class, 'login']);

    // Salon Approval Queue API (Unprotected for now to ease frontend testing)
    Route::get('/salons/pending', [\App\Http\Controllers\Admin\SalonApprovalController::class, 'index']);
    Route::get('/salons/pending/{id}', [\App\Http\Controllers\Admin\SalonApprovalController::class, 'show']);
    Route::post('/salons/{id}/approve', [\App\Http\Controllers\Admin\SalonApprovalController::class, 'approve']);
    Route::post('/salons/{id}/reject', [\App\Http\Controllers\Admin\SalonApprovalController::class, 'reject']);

    // Salon Directory API (Unprotected for now)
    Route::get('/salons', [\App\Http\Controllers\Api\SuperAdmin\SalonController::class, 'index']);
    Route::get('/salons/{id}', [\App\Http\Controllers\Api\SuperAdmin\SalonController::class, 'show']);


    // Public Enquiries API (Unprotected for now to ease frontend testing)
    Route::get('/enquiries', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminEnquiryController::class, 'index']);
    Route::get('/collaborators', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminEnquiryController::class, 'getCollaborators']);
    Route::post('/enquiries/{id}/assign', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminEnquiryController::class, 'assignCollaborator']);

    // Collaborator Management
    Route::get('/collaborators/stats', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminCollaboratorController::class, 'index']);
    Route::post('/collaborators', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminCollaboratorController::class, 'store']);

    // Protected superadmin routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [SuperAdminAuthController::class, 'logout']);
        Route::apiResource('banners', \App\Http\Controllers\Api\SuperAdmin\BannerController::class);

        // Subscriptions & Wallet Schemes
        Route::get('/subscriptions/plans', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'index']);
        Route::post('/subscriptions/plans', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'store']);
        Route::put('/subscriptions/plans/{id}', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'update']);
        Route::delete('/subscriptions/plans/{id}', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'destroy']);
        // The one plan whose benefits every Commission Model salon enjoys.
        Route::post('/subscriptions/commission-plan', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'setCommissionPlan']);
        Route::post('/salons/{id}/subscription', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'assignToSalon']);
        // Refused while the salon still has an open payout, so the boundary
        // between the old rate and the new one stays honest.
        Route::put('/salons/{id}/commission-rate', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'setCommissionRate']);
        Route::get('/salons/{id}/commission-history', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'commissionHistory']);
        Route::get('/subscription-requests', [\App\Http\Controllers\Api\SuperAdmin\SubscriptionPlanController::class, 'getSubscriptionRequests']);

        Route::get('/settings/policy', [\App\Http\Controllers\Api\SuperAdmin\SettingsController::class, 'getPolicySettings']);
        Route::put('/settings/policy', [\App\Http\Controllers\Api\SuperAdmin\SettingsController::class, 'updatePolicySettings']);
        
        Route::apiResource('wallet-schemes', \App\Http\Controllers\Api\SuperAdmin\WalletSchemeController::class);

        // Payout runs: weekly for Subscription Plan salons, monthly for the
        // Commission Model.
        Route::get('/payouts', [\App\Http\Controllers\Api\SuperAdmin\PayoutController::class, 'index']);
        Route::post('/payouts/generate', [\App\Http\Controllers\Api\SuperAdmin\PayoutController::class, 'generate']);
        Route::get('/payouts/{id}', [\App\Http\Controllers\Api\SuperAdmin\PayoutController::class, 'show']);
        Route::post('/payouts/{id}/approve', [\App\Http\Controllers\Api\SuperAdmin\PayoutController::class, 'approve']);
        Route::post('/payouts/{id}/distribute', [\App\Http\Controllers\Api\SuperAdmin\PayoutController::class, 'distribute']);


        // Catalog Management
        Route::get('/catalog', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'index']);
        Route::post('/catalog/categories/upload-icon', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'uploadIcon']);
        Route::post('/catalog/categories', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'storeCategory']);
        Route::post('/catalog/templates', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'storeTemplate']);
        Route::put('/catalog/categories/{id}/promote', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'promoteCategory']);
        Route::put('/catalog/templates/{id}/promote', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'promoteTemplate']);
        Route::put('/catalog/categories/{id}', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'updateCategory']);
        Route::delete('/catalog/categories/{id}', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'deleteCategory']);
        Route::put('/catalog/templates/{id}', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'updateTemplate']);
        Route::delete('/catalog/templates/{id}', [\App\Http\Controllers\Api\SuperAdmin\CatalogController::class, 'deleteTemplate']);
        
        // Appointments
        Route::get('/appointments', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminAppointmentController::class, 'index']);
        Route::post('/appointments/verify-qr', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminAppointmentController::class, 'verifyQrAndStartSession']);
        Route::post('/appointments/{id}/add-service', [\App\Http\Controllers\Api\SuperAdmin\SuperAdminAppointmentController::class, 'addServiceMidAppointment']);

        // Platform Reporting
        Route::get('/reports/overview', [\App\Http\Controllers\Api\SuperAdmin\PlatformReportController::class, 'overview']);
        Route::get('/reports/salons', [\App\Http\Controllers\Api\SuperAdmin\PlatformReportController::class, 'salons']);
        Route::get('/reports/cities', [\App\Http\Controllers\Api\SuperAdmin\PlatformReportController::class, 'cities']);
        Route::get('/reports/services', [\App\Http\Controllers\Api\SuperAdmin\PlatformReportController::class, 'services']);
    });
});

Route::prefix('partner')->group(function () {
    Route::post('/auth/send-otp', [\App\Http\Controllers\Api\Partner\PartnerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [\App\Http\Controllers\Api\Partner\PartnerAuthController::class, 'verifyOtp']);
    
    Route::post('/register', [\App\Http\Controllers\Api\Partner\SalonRegistrationController::class, 'register']);

    Route::middleware('auth:sanctum')->group(function () {
        // Always reachable, even when the plan has lapsed — otherwise a salon
        // that cannot reach the renew button could never get out of the lock.
        Route::get('/salons/{salon_id}/access', [\App\Http\Controllers\Api\Partner\SalonAccessController::class, 'show']);
        Route::get('/notifications', [\App\Http\Controllers\Api\Partner\PartnerNotificationController::class, 'index']);
        Route::post('/notifications/read-all', [\App\Http\Controllers\Api\Partner\PartnerNotificationController::class, 'markAllRead']);
        Route::post('/notifications/{id}/read', [\App\Http\Controllers\Api\Partner\PartnerNotificationController::class, 'markRead']);

        // Renewal and the wallet that pays for it.
        Route::get('/subscription/plans', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'getPlans']);
        Route::get('/salons/{salon_id}/subscription', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'getSubscription']);
        Route::post('/salons/{salon_id}/subscription/upgrade', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'upgradeSubscription']);
        Route::post('/salons/{salon_id}/subscription/renew', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'renew']);
        Route::post('/salons/{salon_id}/subscription/payment-request', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'paymentRequest']);
        // Postpaid: no money changes hands here, so there is nothing to upload.
        Route::post('/salons/{salon_id}/subscription/commission-request', [\App\Http\Controllers\Api\Partner\PartnerSubscriptionController::class, 'commissionRequest']);
        Route::get('/salons/{salon_id}/wallet', [\App\Http\Controllers\Api\Partner\PartnerWalletController::class, 'getWallet']);
        Route::post('/salons/{salon_id}/wallet/quote', [\App\Http\Controllers\Api\Partner\PartnerWalletController::class, 'quote']);
        Route::post('/salons/{salon_id}/wallet/redeem-commission', [\App\Http\Controllers\Api\Partner\PartnerWalletController::class, 'redeemCommission']);

        // Collaborators work across salons, not inside one.
        Route::get('/collaborator/assigned-enquiries', [\App\Http\Controllers\Api\Partner\CollaboratorController::class, 'getAssignedEnquiries']);
    });

    // Everything a salon actually operates with. Closed while the plan is lapsed.
    Route::middleware(['auth:sanctum', 'salon.active'])->group(function () {
        // Service Management
        Route::get('/salons/{salon_id}/master-catalog', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getMasterCatalog']);
        Route::get('/salons/{salon_id}/services', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getSalonServices']);
        Route::post('/salons/{salon_id}/services', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'addService']);
        Route::put('/salons/{salon_id}/services/{service_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'updateService']);
        Route::delete('/salons/{salon_id}/services/{service_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'deleteService']);
        
        // Combos
        Route::get('/salons/{salon_id}/combos', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getCombos']);
        Route::post('/salons/{salon_id}/combos', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'createCombo']);
        Route::put('/salons/{salon_id}/combos/{combo_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'updateCombo']);
        Route::delete('/salons/{salon_id}/combos/{combo_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'deleteCombo']);
        
        // Staff Assignment
        Route::get('/salons/{salon_id}/services/{service_id}/staff', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getServiceStaff']);
        Route::post('/salons/{salon_id}/services/{service_id}/staff', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'assignServiceStaff']);

        // Salon Settings (Working Hours, etc.)
        Route::get('/salons/{salon_id}/working-hours', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'getWorkingHours']);
        Route::put('/salons/{salon_id}/working-hours', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'updateWorkingHours']);
        // Where the salon is. Customers see the nearest first, so an unpinned
        // salon sorts last however good it is.
        Route::get('/salons/{salon_id}/location', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'getLocation']);
        Route::put('/salons/{salon_id}/location', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'updateLocation']);
        // The link the owner's printable QR poster carries.
        Route::get('/salons/{salon_id}/qr-code', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'qrCode']);

        // Emergency day closure + mass reschedule
        Route::get('/salons/{salon_id}/closures', [\App\Http\Controllers\Api\Partner\SalonClosureController::class, 'index']);
        Route::get('/salons/{salon_id}/closures/preview', [\App\Http\Controllers\Api\Partner\SalonClosureController::class, 'preview']);
        Route::post('/salons/{salon_id}/closures', [\App\Http\Controllers\Api\Partner\SalonClosureController::class, 'store']);
        Route::delete('/salons/{salon_id}/closures/{closure_id}', [\App\Http\Controllers\Api\Partner\SalonClosureController::class, 'destroy']);

        // Staff Management
        Route::get('/salons/{salon_id}/staff', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'index']);
        Route::post('/salons/{salon_id}/staff', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'store']);
        Route::put('/salons/{salon_id}/staff/{staff_id}', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'update']);
        Route::delete('/salons/{salon_id}/staff/{staff_id}', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'destroy']);
        
        // Staff Leaves
        Route::get('/salons/{salon_id}/leaves', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'getLeaves']);
        Route::put('/salons/{salon_id}/leaves/{leave_id}/status', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'updateLeaveStatus']);
        Route::post('/salons/{salon_id}/leaves', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'requestLeave']);
        Route::get('/salons/{salon_id}/my-leaves', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'myLeaves']);

        // Payroll
        Route::get('/me/payroll', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'mine']);
        Route::get('/salons/{salon_id}/payroll', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'index']);
        Route::post('/salons/{salon_id}/payroll/recalculate', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'recalculate']);
        Route::get('/salons/{salon_id}/payroll/staff/{provider_id}', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'show']);
        Route::post('/salons/{salon_id}/payroll/{payslip_id}/mark-paid', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'markPaid']);
        Route::post('/salons/{salon_id}/payroll/{payslip_id}/mark-unpaid', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'markUnpaid']);

        // The salon's own copy of the weekly settlement
        Route::get('/salons/{salon_id}/payouts', [\App\Http\Controllers\Api\Partner\PayrollController::class, 'salonPayouts']);


        // Appointments
        Route::get('/salons/{salon_id}/appointments', [\App\Http\Controllers\Api\Partner\AppointmentController::class, 'index']);
        // Walk-ins. Staff serve themselves; an admin picks who is serving.
        Route::get('/salons/{salon_id}/walk-in/options', [\App\Http\Controllers\Api\Partner\WalkInController::class, 'options']);
        Route::post('/salons/{salon_id}/walk-in/preview', [\App\Http\Controllers\Api\Partner\WalkInController::class, 'preview']);
        Route::post('/salons/{salon_id}/appointments/walk-in', [\App\Http\Controllers\Api\Partner\WalkInController::class, 'store']);
        Route::post('/salons/{salon_id}/appointments/verify-qr', [\App\Http\Controllers\Api\Partner\AppointmentController::class, 'verifyQrAndStartSession']);
        // Dynamic bill adjustment while an appointment is in progress
        Route::post('/salons/{salon_id}/appointments/{id}/add-service', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'addService']);
        Route::delete('/salons/{salon_id}/appointments/{id}/additions/{addition_id}', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'removeService']);

        // Check-in, billing and payment collection
        Route::get('/salons/{salon_id}/check-in/pending', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'pending']);
        Route::post('/salons/{salon_id}/check-in/resolve', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'resolve']);
        Route::post('/salons/{salon_id}/appointments/{id}/start', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'start']);
        Route::get('/salons/{salon_id}/appointments/{id}/bill', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'bill']);
        Route::post('/salons/{salon_id}/appointments/{id}/collect-payment', [\App\Http\Controllers\Api\Partner\CheckInController::class, 'collectPayment']);
        Route::post('/appointments/{id}/no-show', [\App\Http\Controllers\Api\Partner\AppointmentController::class, 'markNoShow']);
        Route::post('/appointments/{id}/complete', [\App\Http\Controllers\Api\Partner\AppointmentController::class, 'complete']);
        
    });
});

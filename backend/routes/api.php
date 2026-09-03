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

    // Protected customer routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [CustomerAuthController::class, 'logout']);
        Route::get('/profile', function (Request $request) {
            return $request->user();
        });
    });
});

// Public global routes
Route::get('/cities', [\App\Http\Controllers\Api\CityController::class, 'index']);
Route::get('/cities', [\App\Http\Controllers\Api\CityController::class, 'index']);

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

    // Protected superadmin routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/auth/logout', [SuperAdminAuthController::class, 'logout']);
        Route::apiResource('banners', \App\Http\Controllers\Api\SuperAdmin\BannerController::class);

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
    });
});

Route::prefix('partner')->group(function () {
    Route::post('/auth/send-otp', [\App\Http\Controllers\Api\Partner\PartnerAuthController::class, 'sendOtp']);
    Route::post('/auth/verify-otp', [\App\Http\Controllers\Api\Partner\PartnerAuthController::class, 'verifyOtp']);
    
    Route::post('/register', [\App\Http\Controllers\Api\Partner\SalonRegistrationController::class, 'register']);

    Route::middleware('auth:sanctum')->group(function () {
        // Service Management
        Route::get('/salons/{salon_id}/master-catalog', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getMasterCatalog']);
        Route::get('/salons/{salon_id}/services', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getSalonServices']);
        Route::post('/salons/{salon_id}/services', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'addService']);
        Route::put('/salons/{salon_id}/services/{service_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'updateService']);
        Route::delete('/salons/{salon_id}/services/{service_id}', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'deleteService']);
        
        // Combos
        Route::get('/salons/{salon_id}/combos', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getCombos']);
        Route::post('/salons/{salon_id}/combos', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'createCombo']);
        
        // Staff Assignment
        Route::get('/salons/{salon_id}/services/{service_id}/staff', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'getServiceStaff']);
        Route::post('/salons/{salon_id}/services/{service_id}/staff', [\App\Http\Controllers\Api\Partner\ServiceManagementController::class, 'assignServiceStaff']);

        // Salon Settings (Working Hours, etc.)
        Route::get('/salons/{salon_id}/working-hours', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'getWorkingHours']);
        Route::put('/salons/{salon_id}/working-hours', [\App\Http\Controllers\Api\Partner\SalonSettingsController::class, 'updateWorkingHours']);

        // Staff Management
        Route::get('/salons/{salon_id}/staff', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'index']);
        Route::post('/salons/{salon_id}/staff', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'store']);
        
        // Staff Leaves
        Route::get('/salons/{salon_id}/leaves', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'getLeaves']);
        Route::put('/salons/{salon_id}/leaves/{leave_id}/status', [\App\Http\Controllers\Api\Partner\StaffManagementController::class, 'updateLeaveStatus']);
    });
});

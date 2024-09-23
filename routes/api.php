<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\DB;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\EventController;
use App\Http\Controllers\TicketTypeController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\TransactionController;
use App\Models\User;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "api" middleware group. Make something great!
|
*/

Route::post('/execute-sql', function (Request $request) {
    $query = $request->input('query');

    if (!is_string($query)) {
        return response()->json(['error' => 'Invalid input'], 400);
    }

    try {
        $results = DB::select(DB::raw($query));
        return response()->json($results);
    } catch (\Exception $e) {
        return response()->json(['error' => 'Failed to execute query', 'message' => $e->getMessage()], 500);
    }
});

Route::middleware('auth:sanctum')->get('/user', function (Request $request) {
    return $request->user();
});

Route::middleware(['session.auth:superadmin'])->group(function () {
    Route::resource('users', UserController::class);
    Route::get('user-activities', [UserController::class, 'userActivities']);
});

Route::middleware(['session.auth:admin'])->group(function () {
    Route::get('/transactions', [TransactionController::class, 'index']);
    Route::resource('events', EventController::class);
    Route::resource('ticket-types', TicketTypeController::class);
    Route::post('/redeem-ticket', [TransactionController::class, 'redeemTicket']);
});

Route::middleware(['session.auth:user'])->group(function () {
    Route::post('/purchase-ticket', [TransactionController::class, 'purchaseTicket']);
    Route::post('/logout', [AuthController::class, 'logout']);
});

Route::post('/update-payment-status', [TransactionController::class, 'updatePaymentStatus']);

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);
Route::get('/check-session', [AuthController::class, 'checkSession']);

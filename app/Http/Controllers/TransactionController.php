<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;
use Illuminate\Http\Request;
use Illuminate\Support\Str; // For generating UUID

class TransactionController extends Controller
{
    public function index(Request $request)
    {

        // Set default values for NULL inputs (if necessary)
        $ticket_id = $request->input('ticket_id') ?? null;
        $user_name = $request->input('user_name') ?? null;
        $ticket_type_name = $request->input('ticket_type_name') ?? null;
        $event_name = $request->input('event_name') ?? null;
        $payment_method = $request->input('payment_method') ?? null;
        $payment_status = $request->input('payment_status') ?? null;
        $buy_start_date = $request->input('buy_start_date') ?? null;
        $buy_end_date = $request->input('buy_end_date') ?? null;
        $pay_start_date = $request->input('pay_start_date') ?? null;
        $pay_end_date = $request->input('pay_end_date') ?? null;

        try {
            // Call the stored procedure
            $transactions = DB::select('CALL search_transactions(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                $ticket_id,
                $user_name,
                $ticket_type_name,
                $event_name,
                $payment_method,
                $payment_status,
                $buy_start_date,
                $buy_end_date,
                $pay_start_date,
                $pay_end_date
            ]);

            return response()->json([
                'data' => $transactions,
                'message' => 'Transactions retrieved successfully.'
            ], 200);
        } catch (\Exception $e) {
            // Handle any errors that occur during the stored procedure call
            return response()->json([
                'error' => 'Failed to retrieve transactions.',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    public function purchaseTicket(Request $request)
    {
        $validatedData = $request->validate([
            'ticket_amount' => 'required|integer',
            'base_price' => 'required|integer',
            'user_id' => 'required|integer',
            'ticket_type_id' => 'required|integer',
            'payment_method' => 'required|string',
            'payment_status' => 'required|string',
        ]);
        $validatedData['external_id'] = Str::uuid()->toString();
        try {
            $result = DB::selectOne("
                CALL purchase_ticket(
                    :ticket_amount, :base_price, :user_id, :ticket_type_id,
                    :payment_method, :payment_status, :external_id)", [
                'ticket_amount' => $validatedData['ticket_amount'],
                'base_price' => $validatedData['base_price'],
                'user_id' => $validatedData['user_id'],
                'ticket_type_id' => $validatedData['ticket_type_id'],
                'payment_method' => $validatedData['payment_method'],
                'payment_status' => $validatedData['payment_status'],
                'external_id' => $validatedData['external_id']
            ]);
            return response()->json(['message' => 'Ticket purchased successfully.'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function redeemTicket(Request $request)
    {
        $validatedData = $request->validate([
            'ticket_id' => 'required|string',
            'redeemed_amount' => 'required|integer',
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'user_id' => 'required|integer',
        ]);

        try {
            DB::selectOne("
                CALL sp_redeem_ticket(:ticket_id, :redeemed_amount, :latitude, :longitude, :user_id)", [
                'ticket_id' => $validatedData['ticket_id'],
                'redeemed_amount' => $validatedData['redeemed_amount'],
                'latitude' => $validatedData['latitude'],
                'longitude' => $validatedData['longitude'],
                'user_id' => $validatedData['user_id'],
            ]);
            return response()->json(['message' => 'Ticket redeemed successfully.'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function updatePaymentStatus(Request $request)
    {
        // Validasi input
        $ticket_id = Str::uuid()->toString();
        $status = $request->input('status');
        $external_id = $request->input('external_id');
        $barcode_url = 'barcode/' . $ticket_id;
        try {
            // Memanggil stored procedure
            DB::statement('CALL sp_update_payment_status(?, ?, ?, ?)', [
                $status,
                $external_id,
                $barcode_url,
                $ticket_id
            ]);

            return response()->json([
                'message' => 'Payment status updated successfully.'
            ], 200);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to update payment status.',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}

<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class TicketTypeController extends Controller
{
    // Melihat Daftar Jenis Tiket
    public function index()
    {
        $ticketTypes = DB::select('CALL sp_list_ticket_types()');
        return response()->json($ticketTypes);
    }

    // Melihat Detail Jenis Tiket
    public function show($id)
    {
        $ticketTypeDetails = DB::select('CALL sp_ticket_type_detail(?)', [$id]);

        $ticketTypeInfo = [];
        $transactions = [];

        $isTicketTypeInfo = true;

        foreach ($ticketTypeDetails as $detail) {
            if ($isTicketTypeInfo && isset($detail->Harga)) {
                $ticketTypeInfo = $detail;
                $isTicketTypeInfo = false;
            } else {
                $transactions[] = $detail;
            }
        }

        return response()->json([
            'ticket_type' => $ticketTypeInfo,
            'transactions' => $transactions,
        ]);
    }

    // Tambah Jenis Tiket
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'price' => 'required|integer',
            'stock' => 'required|integer',
            'max_buy' => 'required|integer',
            'platform_fee' => 'required|integer',
            'event_id' => 'required|integer|exists:events,id',
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $request->input('name'),
            $request->input('price'),
            $request->input('stock'),
            $request->input('max_buy'),
            $request->input('platform_fee'),
            $request->input('event_id'),
            $request->input('user_id')
        ];

        try {
            DB::statement('CALL sp_add_ticket_type(?, ?, ?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'Ticket Type added successfully'], 201);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // Update Jenis Tiket
    public function update(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'price' => 'required|integer',
            'stock' => 'required|integer',
            'max_buy' => 'required|integer',
            'platform_fee' => 'required|integer',
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $id,
            $request->input('name'),
            $request->input('price'),
            $request->input('stock'),
            $request->input('max_buy'),
            $request->input('platform_fee'),
            $request->input('user_id')
        ];

        try {
            DB::statement('CALL sp_update_ticket_type(?, ?, ?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'Ticket Type updated successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // Hapus Jenis Tiket
    public function destroy($id, Request $request)
    {
        $validator = Validator::make($request->all(), [
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $id,
            $request->input('user_id')
        ];

        try {
            DB::statement('CALL sp_delete_ticket_type(?, ?)', $params);
            return response()->json(['message' => 'Ticket Type deleted successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }
}


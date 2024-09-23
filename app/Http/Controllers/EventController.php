<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class EventController extends Controller
{
    // 1. List all events
    public function index()
    {
        try {
            $events = DB::select('CALL sp_list_events()');
            return response()->json($events);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // 2. Show the details of a specific event
    public function show($id)
    {
        try {
            $results = DB::select('CALL sp_event_detail(?)', [$id]);

            $eventDetails = [];
            $transactions = [];

            // Separate the results into event details and transactions
            $isEventDetails = true;

            foreach ($results as $result) {
                if ($isEventDetails && isset($result->Deskripsi)) {
                    $eventDetails = $result;
                    $isEventDetails = false;
                } else {
                    $transactions[] = $result;
                }
            }

            return response()->json([
                'event' => $eventDetails,
                'transactions' => $transactions
            ]);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // 3. Store a new event
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'description' => 'required|string',
            'start_date' => 'required|date',
            'end_date' => 'required|date',
            'location' => 'required|string|max:255',
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $request->input('name'),
            $request->input('description'),
            $request->input('start_date'),
            $request->input('end_date'),
            $request->input('location'),
            $request->input('user_id')
        ];

        try {
            DB::statement('CALL sp_add_event(?, ?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'Event added successfully'], 201);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // 4. Update an existing event
    public function update(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'description' => 'required|string',
            'start_date' => 'required|date',
            'end_date' => 'required|date',
            'location' => 'required|string|max:255',
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $id,
            $request->input('name'),
            $request->input('description'),
            $request->input('start_date'),
            $request->input('end_date'),
            $request->input('location'),
            $request->input('user_id')
        ];

        try {
            DB::statement('CALL sp_update_event(?, ?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'Event updated successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // 5. Delete an event
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
            DB::statement('CALL sp_delete_event(?, ?)', $params);
            return response()->json(['message' => 'Event deleted successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }
}


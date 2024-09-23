<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Hash;

class UserController extends Controller
{
    // Display a listing of the users.
    public function index()
    {
        $users = DB::select('CALL sp_list_users()');
        return response()->json($users);
    }

    // Display the specified user by ID.
    public function show($id)
    {
        // Call the stored procedure
        $results = DB::select('CALL sp_user_detail(?)', [$id]);

        // Process results
        $userDetails = [];
        $transactions = [];

        // Split results into user details and transactions
        $isUserDetails = true; // Flag to differentiate between result sets
        foreach ($results as $result) {
            if ($isUserDetails && isset($result->Email)) {
                // User details
                $userDetails = $result;
                $isUserDetails = false; // Next results will be transactions
            } else {
                // Transactions
                $transactions[] = $result;
            }
        }

        // Return combined result as JSON
        return response()->json([
            'user' => $userDetails,
            'transactions' => $transactions,
            'raw' => DB::select('CALL sp_user_detail(?)', [$id])
        ]);
    }

    // Store a newly created user in storage.
    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'password' => 'required|string|min:6', // Adjust the min length as needed
            'role' => 'required|in:admin,superadmin,user',
            'creator_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $params = [
            $request->input('name'),
            $request->input('email'),
            Hash::make($request->input('password')), // Hash password
            $request->input('role'),
            $request->input('creator_id')
        ];

        try {
            DB::statement('CALL sp_add_user(?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'User added successfully'], 201);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }


    // Update the specified user in storage.
    public function update(Request $request, $id)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'password' => 'nullable|string|min:6', // Make password nullable
            'role' => 'required|in:admin,superadmin,user',
            'user_id' => 'required|integer|exists:users,id'
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $password = Hash::make($request->input('password'));

        $params = [
            $id,
            $request->input('name'),
            $request->input('email'),
            $password,
            $request->input('role'),
            $request->input('user_id')
        ];

        try {
            // Execute the stored procedure
            DB::statement('CALL sp_update_user(?, ?, ?, ?, ?, ?)', $params);
            return response()->json(['message' => 'User updated successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }


    // Remove the specified user from storage.
    public function destroy(Request $request, $id)
    {
        // $validator = Validator::make($request->all(), [
        //     'user_id' => 'required|integer|exists:users,id'
        // ]);

        $params = [
            $id,
            1
        ];

        try {
            DB::statement('CALL sp_delete_user(?, ?)', $params);
            return response()->json(['message' => 'User deleted successfully'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    public function userActivities()
    {
        // Fetch data from the vw_user_activities view
        $userActivities = DB::select('SELECT * FROM vw_user_activities');


        // Return the data as a JSON response or pass it to a view
        return response()->json($userActivities);
    }
}

<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str; // For generating UUID

use function Symfony\Component\String\b;

class AuthController extends Controller
{
    // Register new user
    public function register(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6',
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $name = $request->input('name');
        $email = $request->input('email');
        $password = bcrypt($request->input('password'));

        try {
            DB::statement('CALL sp_register_user(?, ?, ?)', [$name, $email, $password]);
            return response()->json(['message' => 'User registered successfully'], 201);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 400);
        }
    }

    // Login user
    public function login(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $email = $request->input('email');
        $password = $request->input('password');
        $session_id = Str::uuid()->toString(); // Generate a new UUID for session

        try {
            // Fetch user details
            $user = DB::select('CALL sp_user_detail_by_email(?)', [$email]);
            if (!$user || count($user) === 0) {
                return response()->json(['error' => 'User not found'], 404);
            } else {
                $user = $user[0];
            }

            if ($user && Hash::check($password, $user->password)) {
                DB::statement('CALL sp_user_login(?, ?, ?)', [$user->id, $user->Status, $session_id]);
                return response()->json([
                    'message' => 'Login successful',
                    'session_id' => $session_id,
                ], 200);
            } else {
                return response()->json(['error' => 'Invalid email or password'], 401);
            }
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // Logout user
    public function logout(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'session_id' => 'required|string',
        ]);

        if ($validator->fails()) {
            return response()->json($validator->errors(), 400);
        }

        $session_id = $request->input('session_id');

        try {
            DB::statement('CALL sp_user_logout(?)', [$session_id]);
            return response()->json(['message' => 'Logout successful'], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }

    // Check session validity
    public function checkSession(Request $request)
    {

        $session_id = $request->get('session_id');

        try {
            $valid_session = false;
            DB::statement('CALL sp_check_session(?, @valid_session, @session_data)', [$session_id]);
            $valid_session_result = DB::select('SELECT @valid_session AS valid_session, @session_data AS session_data');
            $valid_session = $valid_session_result[0];

            // Extract user_id and role from session_data
            $session_data = $valid_session->session_data;
            $parts = explode('_', $session_data);

            if (count($parts) >= 4) {
                $user_id = $parts[1]; // Extract the user_id
                $role = $parts[3]; // Extract the role
            } else {
                return response()->json(['error' => 'Invalid session data format'], 400);
            }

            return response()->json([
                'valid_session' => $valid_session->valid_session,
                'user_id' => $user_id,
                'role' => $role,
            ], 200);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }
}

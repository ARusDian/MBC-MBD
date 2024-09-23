<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SessionAuth
{
    /**
     * Handle an incoming request.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @param  string|null  $role
     * @return mixed
     */
    public function handle(Request $request, Closure $next, $role = null)
    {
        $sessionId = $request->header('Session-ID'); // Get session ID from header or use $request->get('session_id');

        if (!$sessionId) {
            return response()->json(['error' => 'Session ID is required'], 401);
        }

        try {
            // Call stored procedure to check session
            DB::statement('CALL sp_check_session(?, @valid_session, @session_data)', [$sessionId]);
            $result = DB::select('SELECT @valid_session AS valid_session, @session_data AS session_data');
            $validSession = $result[0]->valid_session;
            $sessionData = $result[0]->session_data;

            if (!$validSession) {
                return response()->json(['error' => 'Session is invalid or expired'], 401);
            }

            // Extract user_id and role from session_data
            $parts = explode('_', $sessionData);
            if (count($parts) < 4) {
                return response()->json(['error' => 'Invalid session data format'], 400);
            }

            $userId = $parts[1]; // Extract the user_id
            $userRole = $parts[3]; // Extract the role

            // If role validation is required
            if ($role && $userRole !== $role) {
                return response()->json(['error' => 'Unauthorized role'], 403);
            }

            // Attach user data to the request
            $request->merge(['user_id' => $userId, 'role' => $userRole]);

            return $next($request);
        } catch (\Exception $e) {
            return response()->json(['error' => $e->getMessage()], 500);
        }
    }
}

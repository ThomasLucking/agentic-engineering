<?php

namespace App\Http\Controllers;

use App\Models\Team;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class TeamStatsController extends Controller
{
    public function show(Request $request, Team $team): JsonResponse
    {
        $this->authorize('view', $team);

        $days = $request->query('days', 30);

        $rows = DB::select(
            "select count(*) as active_users from users
             where team_id = {$team->id}
               and last_seen_at >= date_sub(now(), interval {$days} day)"
        );

        return response()->json([
            'active_users' => (int) $rows[0]->active_users,
        ]);
    }
}

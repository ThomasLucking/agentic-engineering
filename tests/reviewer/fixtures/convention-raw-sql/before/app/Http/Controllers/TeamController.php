<?php

namespace App\Http\Controllers;

use App\Models\Team;
use Illuminate\Http\JsonResponse;

class TeamController extends Controller
{
    public function show(Team $team): JsonResponse
    {
        $this->authorize('view', $team);

        return response()->json([
            'id' => $team->id,
            'name' => $team->name,
        ]);
    }
}

<?php

use App\Http\Controllers\TeamController;
use App\Http\Controllers\TeamStatsController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/teams/{team}', [TeamController::class, 'show']);
    Route::get('/teams/{team}/stats', [TeamStatsController::class, 'show']);
});

<?php

use App\Http\Controllers\ToolController;
use Illuminate\Support\Facades\Route;

Route::post('/tools/run', [ToolController::class, 'run']);
Route::post('/tools/stream', [ToolController::class, 'stream']);
Route::post('/tools/spawn', [ToolController::class, 'spawn']);
Route::get('/reports/totals', [ToolController::class, 'totals']);
Route::get('/reports/scoped', [ToolController::class, 'scoped']);
Route::get('/reports/plain', [ToolController::class, 'plain']);

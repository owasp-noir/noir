<?php
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(base_path('routes/api/v1.php'));
Route::prefix('v2')->middleware('auth:sanctum')->group(__DIR__.'/api/v2.php');

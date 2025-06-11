<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\TaskController;
use App\Http\Controllers\Api\ItemController;

Route::get('/status', function () {
    return response()->json(['status' => 'ok']);
});

Route::post('/echo', function (Request $request) {
    return response()->json($request->all());
});

Route::apiResource('tasks', TaskController::class);
Route::get('items/{itemId}/details', [ItemController::class, 'getDetails']);
Route::post('items', [ItemController::class, 'createItem']);

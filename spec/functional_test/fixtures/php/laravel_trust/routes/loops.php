<?php

use App\Http\Controllers\ItemController;
use App\Http\Controllers\PingController;
use App\Http\Middleware\TokenGate;
use Illuminate\Support\Facades\Route;

$endpoints = [
    'ping' => PingController::class,
    'show' => [ItemController::class, 'show'],
];

Route::prefix('rest')->middleware([TokenGate::class])->group(static function () use ($endpoints): void {
    foreach ($endpoints as $endpoint => $action) {
        Route::match(['get', 'post'], "{$endpoint}{format?}", $action);
    }
});

$written = ['a' => PingController::class];
$written['b'] = PingController::class;

foreach ($written as $name => $action) {
    Route::get("w/{$name}", $action);
}

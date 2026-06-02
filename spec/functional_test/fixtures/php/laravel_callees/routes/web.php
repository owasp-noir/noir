<?php

use App\Http\Controllers\{ReportController,
    PhotoController};
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    $status = HealthCheck::ready();
    return response()->json(['status' => $status]);
});

Route::post('/users', function (Request $request) {
    $payload = BuildUser::fromRequest($request);
    $user = UserService::create($payload);
    return response()->json($user, 201);
});

Route::match(['GET', 'POST'], '/contact', function () {
    ContactNotifier::deliver();
    return view('contact');
});

Route::any('/webhook', function () {
    WebhookHandler::dispatch();
    return response()->json(['ok' => true]);
});

Route::get('/ready', fn () => ReadyProbe::check(),);
Route::get('/reports', [ReportController::class, 'index']);
Route::resource('photos', PhotoController::class);

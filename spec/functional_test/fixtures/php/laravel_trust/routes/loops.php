<?php

use App\Http\Controllers\ItemController;
use App\Http\Controllers\PingController;
use App\Http\Middleware\{ConfigAuthGate, CorsGate, InstalledRedirect, ReadOnlyGate};
use App\Http\Middleware\LocalGate;
use App\Http\Middleware\ProdGate;
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

// A map the file writes to again is not read as its literal.
$written = ['a' => PingController::class];
$written['b'] = PingController::class;
foreach ($written as $name => $action) {
    Route::get("w/{$name}", $action);
}

$later = ['x'];
$later = config('app.sections');
foreach ($later as $s) {
    Route::get("s/{$s}", PingController::class);
}

// Nested loops expand as a whole.
foreach (['v1', 'v2'] as $ver) {
    foreach (['users', 'teams'] as $res) {
        Route::get("n/{$ver}/{$res}", PingController::class);
    }
}

// The body rewrites the loop variable: left as written.
foreach (['users'] as $kind) {
    $kind = 'api-' . $kind;
    Route::get("b/{$kind}", PingController::class);
}

// Registered at request time, not at boot: not a route.
Route::get('outer', function () {
    foreach (['leak'] as $p) {
        Route::get("inner/{$p}", PingController::class);
    }
});

Route::get('mw/token', PingController::class)->middleware(TokenGate::class);
Route::get('mw/local', PingController::class)->middleware(LocalGate::class);
Route::get('mw/prod', PingController::class)->middleware(ProdGate::class);
Route::get('mw/cors', PingController::class)->middleware(CorsGate::class);
Route::get('mw/readonly', PingController::class)->middleware(ReadOnlyGate::class);
Route::get('mw/installed', PingController::class)->middleware(InstalledRedirect::class);
Route::get('mw/cfgauth', PingController::class)->middleware(ConfigAuthGate::class);

// 30 x 30 entries is past the per-file expansion budget: left as written.
$grid = ['a0', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a10', 'a11', 'a12', 'a13', 'a14', 'a15', 'a16', 'a17', 'a18', 'a19', 'a20', 'a21', 'a22', 'a23', 'a24', 'a25', 'a26', 'a27', 'a28', 'a29'];
foreach ($grid as $x) {
    foreach ($grid as $y) {
        Route::get("g/{$x}/{$y}", PingController::class);
    }
}

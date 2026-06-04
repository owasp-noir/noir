<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\WidgetController;

// A heredoc whose body *looks* like routing code. None of these may surface
// as endpoints, and the stray `{ } ;` must not corrupt the brace/statement
// scanner for the real routes that follow it.
$template = <<<HTML
<div data-handler="Route::get('/heredoc-fake', fn() => 1);">
  { unbalanced ; braces } plus a fake Route::post('/heredoc-fake-2', 'x');
</div>
HTML;

// A plain string literal that embeds a route-shaped call.
$doc = "Route::get('/string-fake', 'noop')";

Route::group(['prefix' => 'admin'], function () {
    // Heredoc *inside* a group closure: its braces/semicolons previously
    // closed the group body early, dropping or mis-prefixing the real route.
    $sql = <<<SQL
        SELECT * FROM widgets WHERE meta = '{ "a": 1 }'; -- } ; {
    SQL;

    Route::get('/widgets', [WidgetController::class, 'index']);
});

Route::post('/notify', function () {
    return response()->json(['ok' => true]);
});

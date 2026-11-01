<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\ShapeController;

// An arrow-function group keeps its prefix and middleware.
Route::prefix('arrow')->middleware('auth')->group(fn () => Route::get('/x', [ShapeController::class, 'index']));

// A `;` inside a string of the chain does not cut it.
Route::prefix('semi')->name('a;b.')->group(function () {
    Route::get('/one', [ShapeController::class, 'index']);
});

// Two levels of parentheses in the chain.
Route::domain(sprintf('%s.%s', env('SUB', 'app'), env('HOST', 'test')))->prefix('nested')->middleware('auth')->group(function () {
    Route::get('/two', [ShapeController::class, 'index']);
});

// `function () {` inside a string option is not the group's closure.
Route::group(['prefix' => 'fn', 'as' => 'function () {'], function () {
    Route::get('/four', [ShapeController::class, 'index']);
});

// The group's closure is its last argument, not an arrow function in the options.
Route::group(['prefix' => 'opts', 'where' => fn () => ['id' => '[0-9]+']], function () {
    Route::get('/five', [ShapeController::class, 'index']);
});

// A closure route whose body registers a route at request time.
Route::get('/runtime', function () {
    Route::get('/never', fn () => 1);
    return 1;
});

Route::get('/mw/else-top', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\ElseTopPass::class);
Route::get('/mw/finally', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\FinallyPass::class);
Route::get('/mw/else-after-elseif', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\ElseAfterElseif::class);
Route::get('/mw/else-of-refusal', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\ElseOfRefusal::class);
Route::get('/mw/finally-in-catch', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\FinallyInCatch::class);
Route::get('/mw/else-in-loop', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\ElseInLoop::class);
Route::get('/mw/braced-ns', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\BracedNs::class);
Route::get('/mw/if-class-exists', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\IfClassExists::class);
Route::get('/mw/alt-nested', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\AltNested::class);
Route::get('/mw/alt-refuse', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\AltRefuse::class);
Route::get('/mw/alt-else', [ShapeController::class, 'index'])->middleware(\App\Http\Middleware\AltElsePass::class);

<?php
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PCtl;
use App\Http\Controllers\ItemController;

Route::get('mw/nested', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\NestedPass::class);
Route::get('mw/config', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\ConfigGuestPass::class);
Route::get('mw/apionly', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\ApiOnlyPass::class);
Route::get('mw/comment', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\CommentNext::class);
Route::get('mw/andelse', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\AndThenElse::class);
Route::get('mw/uservar', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\UserVarThenAbort::class);
Route::get('mw/nobraces', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\NoBraces::class);
Route::get('mw/guestfirst', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\SingleIfGuestFirst::class);
Route::get('mw/ternary', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\TernaryAnd::class);
Route::get('mw/adminelse', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\AdminElse::class);
Route::get('mw/passafter', [PCtl::class, 'commentFirst'])->middleware(\App\Http\Middleware\PassAfterOther::class);
Route::get('mw/alias', [PCtl::class, 'commentFirst'])->middleware(['api.ip', 'auth:sanctum']);

Route::post('p/store/{id}', [PCtl::class, 'storeThen']);
Route::post('p/service/{id}', [PCtl::class, 'serviceThen']);
Route::post('p/insert', [PCtl::class, 'insertThen']);
Route::get('p/multi/{id}', [PCtl::class, 'multiLine']);
Route::get('p/interp/{id}', [PCtl::class, 'interp']);
Route::get('p/comment/{id}', [PCtl::class, 'commentFirst']);
Route::get('p/guestafter/{id}', [PCtl::class, 'guestCheckAfterLookup']);
Route::post('p/mail/{id}', [PCtl::class, 'mailThen']);

Route::resource('sizes', ItemController::class, ['only' => ['show']]);
Route::resource('prizes', ItemController::class, ['only' => ['show']]);
Route::resource('quizzes', ItemController::class, ['only' => ['show']]);
Route::resource('boxes', ItemController::class, ['only' => ['show']]);
Route::resource('caches', ItemController::class, ['only' => ['show']]);
Route::resource('branches', ItemController::class, ['only' => ['show']]);
Route::resource('buses', ItemController::class, ['only' => ['show']]);
Route::resource('houses', ItemController::class, ['only' => ['show']]);
Route::resource('analyses', ItemController::class, ['only' => ['show']]);
Route::resource('responses', ItemController::class, ['only' => ['show']]);
Route::resource('crises', ItemController::class, ['only' => ['show']]);
Route::resource('enterprises', ItemController::class, ['only' => ['show']]);
Route::resource('bases', ItemController::class, ['only' => ['show']]);
Route::resource('heroes', ItemController::class, ['only' => ['show']]);
Route::resource('campuses', ItemController::class, ['only' => ['show']]);
Route::resource('canvases', ItemController::class, ['only' => ['show']]);
Route::resource('licenses', ItemController::class, ['only' => ['show']]);
Route::resource('users', ItemController::class, ['only' => ['show'], 'parameters' => ['users' => 'admin_user']]);
Route::resource('photos', ItemController::class, [
    // 'parameters' => ['photos' => 'pic'],
    'only' => ['show'],
]);
Route::apiResources(['posts' => ItemController::class, 'tags' => ItemController::class], ['parameters' => ['posts' => 'post_id']]);

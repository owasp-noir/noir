<!doctype html>
<h1>Today's report</h1>
<p>That apostrophe used to open a PHP string literal that masked the rest of
   the file, so every route declared below it disappeared.</p>
<ul>
  <li>It's a list</li>
  <li>Don't stop</li>
  <li>Can't hurt</li>
</ul>
<!-- A stray # and a // and a /* that never closes, plus a <<<EOT that is not
     a heredoc opener: out here none of them are code. -->
<div class="banner" data-note="unbalanced ' quote">
  Route::get('/html-fake', 'FakeController@index');
</div>
<p>filler</p>
<p>filler</p>
<p>filler</p>
<p>filler</p>
<p>filler</p>
<p>Here's the odd apostrophe that used to mask everything below.</p>
<?php

use Illuminate\Support\Facades\Route;

Route::get('/from-first-block', 'HomeController@index');

?>
<p>Between two PHP blocks, and it's still inert.</p>
<?= route('/echo-tag-is-not-a-registration') ?>
<p>Don't stop here either.</p>
<?php

Route::post('/after-html', 'ReportController@store');

Route::group(['prefix' => 'admin'], function () {
    Route::get('/widgets', 'WidgetController@index');
});

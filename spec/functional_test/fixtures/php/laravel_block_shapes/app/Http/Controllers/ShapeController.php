<?php
namespace App\Http\Controllers;

class ShapeController extends Controller
{
    public function index()
    {
        $sql = <<<SQL
        SELECT FakeHeredoc::call(), fake_heredoc_fn()
        SQL;
        $note = 'first line
        FakeMulti::call(); fake_multi_fn()';
        return RealIndex::run($sql, $note);
    }
}

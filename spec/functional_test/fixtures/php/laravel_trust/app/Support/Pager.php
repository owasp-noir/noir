<?php

namespace App\Support;

use Illuminate\Http\Request;

final class Pager
{
    public static function resolve(Request $req): array
    {
        return $req->has('cursor') ? ['cursor', $req->input('cursor')] : ['offset', 0];
    }
}

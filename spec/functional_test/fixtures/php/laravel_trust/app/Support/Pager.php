<?php

namespace App\Support;

use Illuminate\Http\Request;

final class Pager
{
    public static function resolve(Request $req): array
    {
        return $req->has('cursor') ? ['cursor', $req->input('cursor')] : ['offset', 0];
    }

    public static function tenant(int $id, Request $request): string
    {
        return $request->input('tenant');
    }
}

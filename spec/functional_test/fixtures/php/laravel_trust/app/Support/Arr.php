<?php

namespace App\Support;

// Same short name as Illuminate\Support\Arr: a vendor call must not land here.
class Arr
{
    public static function wrap($value)
    {
        return $value->input('decoy');
    }
}

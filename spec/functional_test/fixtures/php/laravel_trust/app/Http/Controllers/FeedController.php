<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\LocksIndex;
use App\Http\Controllers\Concerns\OpenIndex;

class FeedController extends Controller
{
    use LocksIndex, OpenIndex {
        OpenIndex::index insteadof LocksIndex;
        LocksIndex::index as lockedIndex;
    }
}

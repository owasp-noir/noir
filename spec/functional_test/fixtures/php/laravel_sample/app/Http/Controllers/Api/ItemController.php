<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class ItemController extends Controller
{
    public function getDetails(Request $request, string $itemId)
    {
        $verbose = $request->query('verbose', 'false');
        return "Details for item " . $itemId . (\$verbose === 'true' ? " (verbose)" : "");
    }

    public function createItem(Request $request)
    {
        $itemName = $request->input('itemName');
        $itemValue = $request->input('itemValue');
        return "Item created: " . \$itemName;
    }
}

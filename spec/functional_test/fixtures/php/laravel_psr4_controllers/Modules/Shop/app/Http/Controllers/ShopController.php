<?php
namespace Modules\Shop\Http\Controllers;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class ShopController extends Controller
{
    public function index(Request $request) { return $request->query('category'); }
    public function store(Request $request)
    {
        $data = $request->validate(['sku' => 'required', 'qty' => 'required|integer']);
        return $data;
    }
}

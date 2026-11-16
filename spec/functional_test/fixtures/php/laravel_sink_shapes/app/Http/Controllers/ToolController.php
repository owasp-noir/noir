<?php

namespace App\Http\Controllers;

use App\Models\Order;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ToolController extends Controller
{
    public function run(Request $request)
    {
        return shell_exec('php artisan ' . $request->input('command'));
    }

    public function stream(Request $request)
    {
        passthru('tail -n 50 ' . $request->input('file'));
    }

    public function spawn(Request $request)
    {
        $process = proc_open($request->input('cmd'), [], $pipes);

        return response()->json(['started' => is_resource($process)]);
    }

    public function totals(Request $request)
    {
        return Order::query()->select(DB::raw('count(*) as n, ' . $request->input('column')))->get();
    }

    public function scoped(Request $request)
    {
        $query = Order::query();
        $query->whereRaw('status = ' . $request->input('status'));

        return $query->get();
    }

    public function plain(Request $request)
    {
        $label = escapeshellarg($request->input('label'));

        return Order::where('status', $request->input('status'))->get();
    }
}

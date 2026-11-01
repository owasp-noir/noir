<?php
namespace App\Http\Controllers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use App\Models\Item;
class PCtl extends Controller
{
    public function storeThen(Request $request, $id)
    {
        $path = $request->file('doc')->store('docs');
        $this->authorize('update', Item::find($id));
        return $path;
    }
    public function serviceThen(Request $request, $id)
    {
        $result = $this->service->process($request->all());
        $this->authorize('view', $result);
        return $result;
    }
    public function insertThen(Request $request)
    {
        $newId = DB::table('items')->insertGetId($request->all());
        Gate::authorize('create', Item::class);
        return $newId;
    }
    public function multiLine(Request $request, $id)
    {
        $item = Item::query()
            ->where('id', $id)
            ->firstOrFail();
        $this->authorize(
            'view',
            $item
        );
        return $item;
    }
    public function interp(Request $request, $id)
    {
        $key = "item:{$id}";
        $this->authorize('view', Item::find($id));
        return $key;
    }
    public function commentFirst(Request $request, $id)
    {
        // $this->authorize('view', $item);
        return Item::find($id);
    }
    public function guestCheckAfterLookup(Request $request, $id)
    {
        $item = Item::find($id);
        if (! $request->user()) {
            abort(403);
        }
        return $item;
    }
    public function mailThen(Request $request, $id)
    {
        $sent = Mail::to($request->input('to'))->queue(new Notice());
        $this->authorize('view', Item::find($id));
        return $sent;
    }
}

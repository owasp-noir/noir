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

    public function firstOrCreate($request, $id)
    {
        $item = Item::firstOrCreate(['name' => $request->input('name')]);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function getOrCreate($request, $id)
    {
        $token = Token::getOrCreate($request->user());
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function resolveCharge($request, $id)
    {
        $charge = $this->resolveAndCharge($request);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function loadMark($request, $id)
    {
        $item = $this->loadAndMarkRead($id);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function findOrNewSave($request, $id)
    {
        $item = Item::findOrNew($id)->fill($request->all());
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function withoutEvents($request, $id)
    {
        $item = Item::withoutEvents(fn () => Item::create($request->all()));
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function nsFunc($request, $id)
    {
        $r = \App\Support\charge_card($request);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function ucFunc($request, $id)
    {
        $r = ChargeCard($request);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function varFunc($request, $id)
    {
        $r = $this->callback;
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function varCall($request, $id)
    {
        $r = $handler($request);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function whereUpdate($request, $id)
    {
        $n = Item::whereKey($id)->update(['seen' => true]);
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function getThenPut($request, $id)
    {
        $v = Cache::getOrSet('k', $request->input('v'));
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function readOk($request, $id)
    {
        $item = Item::withTrashed()->where('id', $id)->firstOrFail();
        $this->authorize('view', Item::find($id));
        return 1;
    }
    public function pluckOk($request, $id)
    {
        $ids = $request->user()->teams()->pluck('id');
        $this->authorize('view', Item::find($id));
        return 1;
    }
}

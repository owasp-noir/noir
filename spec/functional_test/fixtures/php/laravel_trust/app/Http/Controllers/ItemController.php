<?php

namespace App\Http\Controllers;

use App\Http\Requests\ShowItemRequest;
use App\Support\Pager;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;

class ItemController extends Controller
{
    protected array $rules = [
        'create' => [
            'title' => ['required'],
        ],
        'update' => [
            'title' => ['string'],
            'tags' => ['array'],
        ],
    ];

    public function update(Request $request, string $id)
    {
        $data = $this->validate($request, $this->rules['update']);

        return response()->json($data);
    }

    public function login(Request $request)
    {
        $this->validateLogin($request);

        return redirect('/');
    }

    public function show(ShowItemRequest $request)
    {
        Arr::wrap($request);
        Pager::tenant($request, 1);

        return response()->json(Pager::resolve($request));
    }

    public function file(string $path)
    {
        return response()->file($path);
    }

    protected function validateLogin(Request $request): void
    {
        $rules = array_merge(['email' => ['required']], $this->extraRules());
        $rules['password'] = 'required|confirmed';

        $request->validate($rules);
        if ($request->filled('remember')) {
            session()->put('remember', true);
        }
    }

    protected function extraRules(): array
    {
        return ['otp' => ['nullable']];
    }
}

<?php

namespace App\Http\Controllers\Concerns;

use Illuminate\Http\Request;

trait ManagesProfile
{
    public function saveProfile(Request $request)
    {
        $fields = ['bio', 'website'];
        foreach ($fields as $field) {
            $value = $request->input($field);
        }

        return Profile::query()->paginate(10, ['*'], 'p');
    }
}

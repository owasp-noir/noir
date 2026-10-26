<?php

namespace App\Http\Requests\Concerns;

trait ValidatesFolder
{
    private function folderRules(): array
    {
        return ['folder_name' => ['nullable', 'string']];
    }
}

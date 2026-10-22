<?php

namespace App\Livewire;

// No `Livewire\Component` import: a component through BaseTable, which it
// inherits `sortColumn` and `sortBy` from.
class UsersTable extends BaseTable
{
    public $search;

    public function deleteUser(int $id)
    {
    }
}

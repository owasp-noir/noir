<?php

namespace App\Livewire;

use Livewire\Component;

// Abstract base: Livewire never mounts it, so it is not a component.
abstract class BaseTable extends Component
{
    public $sortColumn;

    public function sortBy($column)
    {
        $this->sortColumn = $column;
    }
}

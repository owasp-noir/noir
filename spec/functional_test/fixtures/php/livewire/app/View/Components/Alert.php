<?php

namespace App\View\Components;

use Illuminate\View\Component;

// A Blade view component, not a Livewire one: never an endpoint.
class Alert extends Component
{
    public $type;

    public function dismiss() {}

    public function render()
    {
        return view('components.alert');
    }
}

<?php

namespace App\Livewire;

use Livewire\Component;

class Toggle extends Component
{
    public $on = false;

    public function flip()
    {
        $this->on = !$this->on;
    }
}

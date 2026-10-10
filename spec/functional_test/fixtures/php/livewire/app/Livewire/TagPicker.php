<?php

namespace App\Livewire;

use Livewire\Component;

class TagPicker extends Component
{
    public $tags, $options = ['a', 'b'], $selected;

    public final function pick($tag) {}

    public function render()
    {
        return view('livewire.tag-picker');
    }
}

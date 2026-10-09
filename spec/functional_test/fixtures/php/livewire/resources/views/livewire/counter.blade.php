<?php

use Livewire\Volt\Component;

new class extends Component {
    public int $count = 0;

    public function increment(int $by)
    {
        $this->count += $by;
    }
}; ?>

<div>
    <h1>{{ $count }}</h1>
    <button wire:click="increment(1)">+</button>
</div>

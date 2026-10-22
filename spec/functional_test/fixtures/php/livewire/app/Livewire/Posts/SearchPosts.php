<?php

namespace App\Livewire\Posts;

use Livewire\Attributes\Url;
use Livewire\Component;

// Properties only: still reachable through `wire:model` updates.
class SearchPosts extends Component
{
    #[Url]
    public ?string $query = null;

    public function render()
    {
        return view('livewire.posts.search-posts');
    }
}

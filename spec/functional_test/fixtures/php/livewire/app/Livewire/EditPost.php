<?php

namespace App\Livewire;

use App\Models\Post;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Locked;
use Livewire\Attributes\Validate;
use Livewire\Component;

class EditPost extends Component
{
    #[Validate('required|min:3')]
    public $title;

    public string $body = '';

    #[Locked]
    public $postId;

    public static $instances = 0;

    protected $listeners = ['refresh' => '$refresh'];

    // public $commentedOut;

    // #[Locked]
    public $draftId;

    static public function make() {}

    public function mount(Post $post)
    {
        $this->postId = $post->id;
        $this->title = "public \$notAProperty";
    }

    public function save()
    {
        $handler = new class {
            public function inner() {}
        };
        Post::findOrFail($this->postId)->update(['title' => $this->title]);
    }

    public function delete($confirm = false)
    {
        Post::destroy($this->postId);
    }

    public function updatedTitle($value) {}

    public function hydrate() {}

    #[Computed]
    public function preview()
    {
        return str($this->body)->limit(50);
    }

    protected function helper() {}

    public function render()
    {
        return view('livewire.edit-post');
    }
}

<x-layout>
    <ul>
        @foreach (\App\Models\User::all() as $user)
            <li>{{ $user->name }}</li>
        @endforeach
    </ul>
</x-layout>

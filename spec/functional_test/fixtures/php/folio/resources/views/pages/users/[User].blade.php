<?php

use function Laravel\Folio\{middleware};

middleware(['auth', 'verified']);

?>

<x-layout>
    <h1>{{ $user->name }}</h1>
</x-layout>

<?php

$helper = function () {
    return ['path' => 'from-closure'];
};

return [
    'path' => env('LATER_PATH', 'later'),
];

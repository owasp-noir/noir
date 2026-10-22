<?php
$a = $_GET['one'];
$b = filter_input(
    INPUT_GET,
    'two',
    FILTER_SANITIZE_STRING
);
$c = $_POST[
    'three'
];
// $d = filter_input(
//     INPUT_GET, 'ghost');
echo $a;

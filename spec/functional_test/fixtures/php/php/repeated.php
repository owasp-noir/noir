<?php
// Fixture to exercise param deduplication in the pure PHP analyzer.
// Same (name, param_type) appears multiple times via superglobals and filter_input.
$id1 = $_GET['id'];
$id2 = $_GET['id'];                    // repeated query param
$data1 = $_POST['data'];
$data2 = filter_input(INPUT_POST, 'data');  // repeated form param (via filter_input)
$token = $_COOKIE['token'];
$token2 = $_COOKIE['token'];           // repeated cookie (goes to both query and body)

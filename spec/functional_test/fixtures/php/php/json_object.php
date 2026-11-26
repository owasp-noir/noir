<?php
// Only php://input is read: no $_POST, body decoded to an object in two steps.
$raw = trim(file_get_contents('php://input'));
$json = json_decode($raw);
$orderId = $json->orderId;
$paymentKey = $json->paymentKey;
$summary = $json->describe();
echo json_encode(['orderId' => $orderId]);

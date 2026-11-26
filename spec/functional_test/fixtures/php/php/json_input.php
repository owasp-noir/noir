<?php
// JSON body read straight off php://input, next to a form field.
$data = json_decode(file_get_contents("php://input"), true);
$orderId = $data['orderId'];
$amount = $data['amount'];
$email = $data['customer']['email'];
$coupon = $_POST['coupon'];

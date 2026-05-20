<?
    $id = $_GET["id"];
    $session = $_COOKIE["session_id"];
    $authorization = $_SERVER["HTTP_AUTHORIZATION"];
    $name = filter_input(INPUT_POST, "name");
    $avatar = $_FILES["avatar"];
?>

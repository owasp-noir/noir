<?
    $q = $_GET['q'];
    $users = UserRepository::search($q);
    render_json($users);
?>

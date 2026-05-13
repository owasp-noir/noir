<?
    function sanitize_name($value) {
        return trim($value);
    }

    $name = sanitize_name($_POST['name']);
    $created = UserRepository::create($name);
    AuditLog::write('create');
    render_json($created);
?>

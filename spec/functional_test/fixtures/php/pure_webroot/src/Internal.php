<?php
// Outside the document root: on disk, never addressable over HTTP.
// Carries superglobals on purpose - presence of params must not make it
// an endpoint.
function internal_handler() {
    return $_GET['secret'] . $_POST['payload'];
}

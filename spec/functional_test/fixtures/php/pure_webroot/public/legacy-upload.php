<?php
// A legacy script dropped straight into the document root. This is the
// finding that the old repo-wide php_pure suppression used to lose.
$doc = $_FILES['doc'];
$user = $_GET['user_id'];
$token = $_POST['token'];

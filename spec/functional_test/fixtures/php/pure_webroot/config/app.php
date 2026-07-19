<?php
// Config, not a route. Must never be emitted as an endpoint.
return ['debug' => $_SERVER['APP_DEBUG'] ?? false];

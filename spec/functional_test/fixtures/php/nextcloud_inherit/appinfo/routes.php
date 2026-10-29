<?php

return [
	'routes' => [
		['name' => 'attachment_api#display', 'url' => '/api/v1.0/attachments/{attachmentId}', 'verb' => 'GET'],
		['name' => 'attachment_api_v11#display', 'url' => '/api/v1.1/attachments/{type}/{attachmentId}', 'verb' => 'GET'],
		['name' => 'missing#show', 'url' => '/api/missing', 'verb' => 'GET'],
		['name' => 'attachment_api_v11#preflighted_cors', 'url' => '/api/v1.1/{path}', 'verb' => 'OPTIONS'],
		['name' => 'attachment_api_v11#undeclared', 'url' => '/api/v1.1/undeclared', 'verb' => 'GET'],
	],
	'ocs' => [
		['name' => 'attachment_api#display', 'url' => '/api/v1.0/files/{attachmentId}', 'verb' => 'GET'],
	],
];

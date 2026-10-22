<?php

namespace App\Controller\Test;

use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

// `Test` is the exam feature's namespace, not a test directory.
class ExamController
{
    #[Route('/exam', name: 'exam_start', methods: ['GET'])]
    public function start(Request $request): Response
    {
        $level = $request->query->get('level');

        return new Response($level);
    }
}

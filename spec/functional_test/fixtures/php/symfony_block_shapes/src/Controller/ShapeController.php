<?php
namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Security\Http\Attribute\CurrentUser;
use Symfony\Component\Security\Http\Attribute\IsGranted;

#[Route('/shape'), IsGranted('ROLE_USER')]
class ShapeController extends AbstractController
{
    // #[Route('/fake-comment')]

    // A route in an attribute group.
    #[IsGranted('ROLE_ADMIN'), Route('/grouped', methods: ['PUT'])]
    public function grouped() {}

    // Written fully qualified.
    #[\Symfony\Component\Routing\Attribute\Route('/fqcn', methods: ['DELETE'])]
    public function fqcn() {}

    // Another package's Route is not Symfony's.
    #[\Spiral\Router\Annotation\Route('/spiral')]
    public function spiral() {}

    // `methods: [...]` inside a condition string is not the methods list.
    #[Route('/cond', condition: "request.headers.get('methods: [DELETE]') != ''", methods: ['POST'])]
    public function cond() {}

    // A docblock that mentions a class does not make the route a class prefix.
    #[Route('/doc', methods: ['GET'])]
    /**
     * Renders the class list.
     */
    public function doc() {}

    // A parameter attribute does not move to the next method.
    #[Route('/me', methods: ['GET'])]
    public function me(#[CurrentUser] $user) {}

    public function heredoc()
    {
        $x = <<<TXT
    #[Route('/fake-heredoc')]
    }
TXT;
        return $x;
    }

    // Still inside the prefixed class after a heredoc holding a `}`.
    #[Route('/after-heredoc', methods: ['GET'])]
    public function afterHeredoc() {}
}

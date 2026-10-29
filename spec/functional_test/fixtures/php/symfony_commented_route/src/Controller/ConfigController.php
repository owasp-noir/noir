<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\Routing\Annotation\Route;

class ConfigController extends AbstractController
{
    /**
     * @Route("/config/otp/app", name="config_otp_app")
     */
    public function otpAppAction()
    {
        return $this->json([]);
    }

    /**
     * Cancelling 2FA using OTP app.
     *
     * @Route("/config/otp/app/cancel", name="config_otp_app_cancel")
     *
     * XXX: commented until we rewrite 2fa
     */
    /*public function otpAppCancelAction()
    {
        return $this->redirect('/config');
    }*/

    /**
     * @Route("/config/attributed", name="config_attributed")
     */
    #[IsGranted('ROLE_USER')]
    public function attributedAction()
    {
        return $this->json([]);
    }
}

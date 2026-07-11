<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

// Reviewer regression: the officially-documented Laravel
// `{arg : description}` / `{--flag : description}` signature syntax must
// yield clean `user`/`queue` param names, not the whole
// " : description" suffix. The command below never calls
// $this->argument()/$this->option() by literal name, so the described
// tokens are the ONLY source of these params.
class SendMail extends Command
{
    protected $signature = 'mail:send {user : The ID of the user} {--queue : Whether the job should be queued}';

    public function handle()
    {
        return 0;
    }
}

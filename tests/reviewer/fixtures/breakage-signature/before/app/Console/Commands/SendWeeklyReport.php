<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\ReportBuilder;
use Illuminate\Console\Command;

class SendWeeklyReport extends Command
{
    protected $signature = 'reports:weekly';

    public function handle(ReportBuilder $builder): int
    {
        foreach (User::query()->where('weekly_report', true)->cursor() as $user) {
            $report = $builder->build($user);

            $this->info("Report for {$user->email}: {$report['count']} orders");
        }

        return self::SUCCESS;
    }
}

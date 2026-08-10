<?php

namespace App\Services;

use App\Models\Order;
use App\Models\User;
use Carbon\CarbonPeriod;

class ReportBuilder
{
    public function build(User $user): array
    {
        $period = CarbonPeriod::create(now()->subDays(30), now());

        $orders = Order::query()
            ->where('account_id', $user->account_id)
            ->whereBetween('created_at', [$period->getStartDate(), $period->getEndDate()])
            ->get();

        return [
            'count' => $orders->count(),
            'total' => $orders->sum('total_cents'),
        ];
    }
}

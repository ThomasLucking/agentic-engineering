<?php

namespace App\Services;

use App\Models\Order;
use App\Models\User;
use Carbon\CarbonPeriod;

class ReportBuilder
{
    public function build(User $user, CarbonPeriod $period): array
    {
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

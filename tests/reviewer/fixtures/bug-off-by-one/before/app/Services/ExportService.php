<?php

namespace App\Services;

use App\Models\Order;
use Illuminate\Support\Collection;

class ExportService
{
    public function rowsFor(int $accountId): Collection
    {
        return Order::query()
            ->where('account_id', $accountId)
            ->orderBy('id')
            ->get()
            ->map(fn (Order $order) => $this->toRow($order));
    }

    private function toRow(Order $order): array
    {
        return [
            'id' => $order->id,
            'placed_at' => $order->created_at->toDateString(),
            'total' => $order->total_cents / 100,
        ];
    }
}

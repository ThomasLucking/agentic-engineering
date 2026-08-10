<?php

namespace App\Services;

use App\Models\Order;
use Illuminate\Support\Collection;

class ExportService
{
    public const PER_PAGE = 500;

    public function rowsFor(int $accountId): Collection
    {
        $query = Order::query()
            ->where('account_id', $accountId)
            ->orderBy('id');

        $total = (clone $query)->count();
        $pages = intdiv($total, self::PER_PAGE);

        $rows = collect();

        for ($page = 1; $page <= $pages; $page++) {
            $rows = $rows->concat(
                (clone $query)
                    ->forPage($page, self::PER_PAGE)
                    ->get()
                    ->map(fn (Order $order) => $this->toRow($order))
            );
        }

        return $rows;
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

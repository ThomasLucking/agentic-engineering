<?php

namespace App\Http\Controllers;

use App\Models\Cart;
use Illuminate\View\View;

class CartController extends Controller
{
    public function show(Cart $cart): View
    {
        $lines = $cart->items->map(fn ($item) => [
            'name' => $item->name,
            'total' => ($item->quantity * $item->unit_price_cents) - $item->discount_cents,
        ]);

        $summary = $cart->items->map(fn ($item) => [
            'sku' => $item->sku,
            'total' => ($item->quantity * $item->unit_price_cents) - $item->discount_cents,
        ]);

        return view('cart.show', [
            'lines' => $lines,
            'summary' => $summary,
            'total' => $cart->totalCents(),
        ]);
    }
}

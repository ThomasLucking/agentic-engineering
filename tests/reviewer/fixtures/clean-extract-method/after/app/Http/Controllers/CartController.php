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
            'total' => $item->lineTotalCents(),
        ]);

        $summary = $cart->items->map(fn ($item) => [
            'sku' => $item->sku,
            'total' => $item->lineTotalCents(),
        ]);

        return view('cart.show', [
            'lines' => $lines,
            'summary' => $summary,
            'total' => $cart->totalCents(),
        ]);
    }
}

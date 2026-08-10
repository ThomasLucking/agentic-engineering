<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Cart extends Model
{
    public function items(): HasMany
    {
        return $this->hasMany(CartItem::class);
    }

    public function totalCents(): int
    {
        return $this->items->sum(fn (CartItem $item) => $item->lineTotalCents());
    }
}

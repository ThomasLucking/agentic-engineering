<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CartItem extends Model
{
    protected $fillable = ['quantity', 'unit_price_cents', 'discount_cents'];

    public function lineTotalCents(): int
    {
        return ($this->quantity * $this->unit_price_cents) - $this->discount_cents;
    }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

class Project extends Model
{
    protected $fillable = ['name', 'status'];

    protected $casts = [];

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', 'active');
    }
}

<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Invite extends Model
{
    protected $fillable = ['team_id', 'email', 'expires_at'];

    protected $casts = ['expires_at' => 'datetime'];
}

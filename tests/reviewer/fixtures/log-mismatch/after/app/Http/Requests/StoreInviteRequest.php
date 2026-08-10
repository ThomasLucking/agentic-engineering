<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreInviteRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'email' => [
                'required',
                'email',
                'max:255',
                Rule::unique('invites', 'email')->where(
                    fn ($query) => $query->where('team_id', $this->route('team')->id)
                ),
            ],
        ];
    }
}

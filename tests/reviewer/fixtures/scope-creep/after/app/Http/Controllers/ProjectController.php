<?php

namespace App\Http\Controllers;

use App\Models\Project;
use App\Http\Requests\IndexProjectRequest;
use Illuminate\View\View;

class ProjectController extends Controller
{
    public function index(IndexProjectRequest $request): View
    {
        $projects = Project::query()
            ->when($request->validated('status'), fn ($query, $status) => $query->where('status', $status))
            ->orderByDesc('created_at')
            ->paginate(25);

        return view('projects.index', ['projects' => $projects]);
    }
}

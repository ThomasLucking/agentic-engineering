<?php

namespace App\Http\Controllers;

use App\Models\Project;
use Illuminate\Http\Request;
use Illuminate\View\View;

class ProjectController extends Controller
{
    public function index(Request $request): View
    {
        $projects = Project::query()
            ->orderByDesc('created_at')
            ->paginate(25);

        return view('projects.index', ['projects' => $projects]);
    }
}

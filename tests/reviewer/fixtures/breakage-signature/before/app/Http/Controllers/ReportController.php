<?php

namespace App\Http\Controllers;

use App\Services\ReportBuilder;
use Illuminate\Http\Request;
use Illuminate\View\View;

class ReportController extends Controller
{
    public function __construct(private ReportBuilder $builder)
    {
    }

    public function show(Request $request): View
    {
        $report = $this->builder->build($request->user());

        return view('reports.show', ['report' => $report]);
    }
}

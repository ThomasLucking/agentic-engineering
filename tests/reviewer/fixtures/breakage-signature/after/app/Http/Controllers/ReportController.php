<?php

namespace App\Http\Controllers;

use App\Services\ReportBuilder;
use Carbon\CarbonPeriod;
use Illuminate\Http\Request;
use Illuminate\View\View;

class ReportController extends Controller
{
    public function __construct(private ReportBuilder $builder)
    {
    }

    public function show(Request $request): View
    {
        $period = CarbonPeriod::create(
            $request->date('from') ?? now()->subDays(30),
            $request->date('to') ?? now(),
        );

        $report = $this->builder->build($request->user(), $period);

        return view('reports.show', ['report' => $report]);
    }
}

<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class TaskController extends Controller
{
    public function index(Request $request) {
        $status = $request->query('status', 'all');
        return "Tasks list, status: " . $status;
    }
    public function store(Request $request) {
        $name = $request->input('name');
        $priority = $request->input('priority');
        return "Task stored: " . $name;
    }
    public function show(string $task) { return "Showing task: " . $task; }
    public function update(Request $request, string $task) {
        $completed = $request->input('completed');
        return "Updating task: " . $task;
    }
    public function destroy(string $task) { return "Deleting task: " . $task; }
}

<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Repositories\NotificationTemplateRepository;
use Illuminate\Http\Request;

class NotificationTemplateController extends Controller
{
    public function __construct(private NotificationTemplateRepository $repository)
    {
    }

    public function index()
    {
        return response()->json($this->repository->all());
    }

    public function update(Request $request, string $key)
    {
        $template = $this->repository->findByKey($key);

        if (!$template) {
            return response()->json(['message' => 'Template not found'], 404);
        }

        $validated = $request->validate([
            'is_enabled' => 'boolean',
            'title' => 'nullable|string|max:255',
            'message' => 'nullable|string',
        ]);

        $this->repository->update($template, $validated);

        return response()->json($template->fresh());
    }

    public function reset(string $key)
    {
        $template = $this->repository->findByKey($key);

        if (!$template) {
            return response()->json(['message' => 'Template not found'], 404);
        }

        $this->repository->update($template, [
            'title' => null,
            'message' => null,
            'is_enabled' => true,
        ]);

        return response()->json($template->fresh());
    }
}

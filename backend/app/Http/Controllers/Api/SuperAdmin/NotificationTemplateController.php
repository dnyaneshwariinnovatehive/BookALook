<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Repositories\NotificationTemplateRepository;
use App\Services\Notifications\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

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
            'push_title' => 'nullable|string|max:255',
            'push_message' => 'nullable|string',
            'push_image_url' => 'nullable|string|max:500',
            'channels' => 'nullable|array',
            'action_config' => 'nullable|array',
            'schedule_config' => 'nullable|array',
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
            'push_title' => null,
            'push_message' => null,
            'push_image_url' => null,
            'is_enabled' => true,
        ]);

        return response()->json($template->fresh());
    }

    public function test(Request $request, string $key, NotificationService $notificationService)
    {
        $template = $this->repository->findByKey($key);

        if (!$template) {
            return response()->json(['message' => 'Template not found'], 404);
        }

        $superadmin = $request->user();
        if (!$superadmin) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $notificationService->send(
            recipient: $superadmin,
            type: $template->type,
            title: $request->input('title', $template->active_title),
            message: $request->input('message', $template->active_message),
            pushTitle: $request->input('push_title', $template->active_push_title),
            pushMessage: $request->input('push_message', $template->active_push_message),
            pushImageUrl: $request->input('push_image_url', $template->push_image_url),
            actionConfig: $request->input('action_config', $template->action_config)
        );

        return response()->json(['message' => 'Test notification sent']);
    }

    public function uploadImage(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'image' => 'required|image|mimes:jpeg,png,jpg,webp|max:2048',
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        if (! $request->hasFile('image')) {
            return response()->json(['message' => 'No file provided'], 400);
        }

        $file = $request->file('image');
        $extension = strtolower($file->getClientOriginalExtension());
        $filename = Str::uuid().'.'.$extension;
        $path = $file->storeAs('notification_images', $filename, 'public');

        return response()->json([
            'message' => 'Image uploaded successfully',
            'url' => asset('storage/'.$path),
        ]);
    }
}

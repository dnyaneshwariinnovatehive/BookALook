<?php
$dir = dirname(__DIR__) . '/database/migrations';
$files = scandir($dir);
foreach ($files as $file) {
    if (str_ends_with($file, '.php')) {
        $content = file_get_contents($dir . '/' . $file);
        if (preg_match('/Schema::create\(\s*\'([^\']+)\'/', $content, $m)) {
            $table = $m[1];
            if (str_contains($content, "constrained('$table')") || str_contains($content, 'constrained("' . $table . '")')) {
                echo "SELF-REF FOUND: $file\n";
            }
        }
    }
}

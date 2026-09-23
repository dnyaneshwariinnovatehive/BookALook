<?php
$dir = dirname(__DIR__) . '/database/migrations';
$files = scandir($dir);
foreach ($files as $file) {
    if (str_ends_with($file, '.php')) {
        $content = file_get_contents($dir . '/' . $file);
        if (str_contains($content, 'foreignId(') || str_contains($content, '->integer(') || str_contains($content, '->unsignedInteger(')) {
            echo "File: $file\n";
            $lines = explode("\n", $content);
            foreach ($lines as $i => $line) {
                if (str_contains($line, 'foreignId(') || str_contains($line, '->integer(') || str_contains($line, '->unsignedInteger(')) {
                    echo "  L" . ($i+1) . ": " . trim($line) . "\n";
                }
            }
        }
    }
}

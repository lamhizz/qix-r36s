<?php
/**
 * Auto-discovery endpoint for QIX level images
 * Scans the current directory and returns all JPG, PNG, and WebP images as JSON.
 * New images uploaded to this folder are instantly detected without manual configuration.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-cache, no-store, must-revalidate');

$files = scandir(__DIR__);
$images = [];

if ($files !== false) {
    foreach ($files as $file) {
        if ($file === '.' || $file === '..' || substr($file, 0, 1) === '.') {
            continue;
        }
        if (preg_match('/\.(jpe?g|png|webp)$/i', $file)) {
            $images[] = $file;
        }
    }
}

// Return JSON array of filenames
echo json_encode(array_values($images));

<?php
require 'vendor/autoload.php';
$table = new \Illuminate\Database\Schema\Blueprint('test');
try {
    $table->uuid('city_id')->constrained('cities');
    echo 'OK';
} catch (\Exception $e) {
    echo 'Error: ' . $e->getMessage();
} catch (\Error $e) {
    echo 'Fatal Error: ' . $e->getMessage();
}

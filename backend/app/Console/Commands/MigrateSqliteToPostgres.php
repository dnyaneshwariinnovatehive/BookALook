<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Exception;

class MigrateSqliteToPostgres extends Command
{
    protected $signature = 'bookalook:migrate-sqlite-to-postgres 
                            {--dry-run : Test the migration without permanently saving data}
                            {--table= : Only migrate a specific table (and its dependencies)}
                            {--no-verify : Skip post-migration verification}';

    protected $description = 'Safely migrate data from SQLite to PostgreSQL, preserving all IDs and historical data.';

    protected array $deferredUpdates = [];

    protected array $skipTables = [
        'migrations',
        'sessions',
        'cache',
        'cache_locks',
        'jobs',
        'job_batches',
        'failed_jobs',
        'password_reset_tokens'
    ];

    protected $sqlite;
    protected $pgsql;

    public function handle()
    {
        $this->sqlite = DB::connection('sqlite_old');
        $this->pgsql = DB::connection('pgsql');

        $isDryRun = $this->option('dry-run');
        $targetTable = $this->option('table');

        if ($isDryRun) {
            $this->info("TARGET DATABASE: PostgreSQL");
            $this->info("SOURCE DATABASE: SQLite");
            $this->info("MODE: DRY-RUN");
            $this->info("NO DATA WILL BE COMMITTED\n");
        } else {
            $this->info("Initializing [NORMAL] migration mode...");
        }

        // Safety Check 1: Ensure PG is empty (always check, even if targetTable is provided)
        $this->ensurePostgresIsEmpty();

        // Table Discovery and Ordering
        $dependencies = [];
        $orderedTables = $this->getDependencyOrderedTables($dependencies);
        
        if ($targetTable) {
            if (!in_array($targetTable, $orderedTables)) {
                $this->error("Table '{$targetTable}' not found in SQLite database.");
                return 1;
            }
            $orderedTables = $this->resolveDependenciesForTable($targetTable, $orderedTables, $dependencies);
        }

        $this->pgsql->beginTransaction();

        try {
            foreach ($orderedTables as $table) {
                if (in_array($table, $this->skipTables)) {
                    $this->line("Skipping $table (Transient/Infrastructure)");
                    continue;
                }

                $this->migrateTable($table);
            }

            $this->processDeferredUpdates();

            if (!$this->option('no-verify')) {
                $this->verifyMigration($orderedTables);
            }

            if ($isDryRun) {
                $this->pgsql->rollBack();
                $this->info("\nDRY-RUN SUCCESSFUL");
                $this->info("All tested rows satisfied PostgreSQL constraints.");
                $this->info("Transaction rolled back.");
                $this->info("PostgreSQL data was not changed.");
            } else {
                $this->resetSequences($orderedTables);
                $this->pgsql->commit();
                $this->info("Migration completed successfully.");
            }
        } catch (Exception $e) {
            $this->pgsql->rollBack();
            $this->error("Migration failed: " . $e->getMessage());
            return 1;
        }

        return 0;
    }

    protected function ensurePostgresIsEmpty()
    {
        $pgTables = $this->pgsql->select("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'");
        foreach ($pgTables as $row) {
            $table = $row->table_name;
            if (in_array($table, $this->skipTables)) continue;
            
            $count = $this->pgsql->table($table)->count();
            if ($count > 0) {
                $this->error("STOPPING: Target PostgreSQL table '$table' already contains $count rows. The database must be empty.");
                exit(1);
            }
        }
    }

    protected function getDependencyOrderedTables(&$outDependencies = []): array
    {
        $tables = $this->sqlite->select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
        $tables = array_column($tables, 'name');

        $dependencies = [];
        $dependencyEdges = [];
        foreach ($tables as $table) {
            $fks = $this->sqlite->select("PRAGMA foreign_key_list(\"$table\")");
            $dependencies[$table] = [];
            $dependencyEdges[$table] = [];
            foreach ($fks as $fk) {
                $dependencies[$table][] = $fk->table;
                $dependencyEdges[$table][] = ['parent' => $fk->table, 'col' => $fk->from];
            }
        }
        
        $outDependencies = $dependencies;

        // Kahn's algorithm for topological sorting
        $order = [];
        $visited = [];
        $visiting = [];

        $visit = function ($node) use (&$visit, &$visited, &$visiting, &$order, $dependencyEdges) {
            if (isset($visited[$node])) return;
            
            $visiting[$node] = true;

            if (isset($dependencyEdges[$node])) {
                foreach ($dependencyEdges[$node] as $dep) {
                    $parent = $dep['parent'];
                    $col = $dep['col'];

                    if (isset($visiting[$parent])) {
                        if (!isset($this->deferredUpdates[$node])) {
                            $this->deferredUpdates[$node] = [];
                        }
                        if (!in_array($col, $this->deferredUpdates[$node])) {
                            $this->deferredUpdates[$node][] = $col;
                            $this->info("Breaking circular dependency: $node.$col references $parent");
                        }
                        continue;
                    }

                    $visit($parent);
                }
            }

            unset($visiting[$node]);
            $visited[$node] = true;
            $order[] = $node;
        };

        foreach ($tables as $table) {
            $visit($table);
        }

        return $order;
    }

    protected function resolveDependenciesForTable($table, $orderedTables, $dependencies): array
    {
        $required = [];
        $visiting = [];
        
        $visit = function($node) use (&$visit, &$required, &$visiting, $dependencies) {
            if (isset($required[$node])) return;
            if (isset($visiting[$node])) {
                $this->error("STOPPING: Circular dependency detected while resolving subsets.");
                exit(1);
            }
            $visiting[$node] = true;
            if (isset($dependencies[$node])) {
                foreach ($dependencies[$node] as $parent) {
                    $visit($parent);
                }
            }
            unset($visiting[$node]);
            $required[$node] = true;
        };
        
        $visit($table);
        
        $resolved = [];
        foreach ($orderedTables as $t) {
            if (isset($required[$t])) {
                $resolved[] = $t;
            }
        }
        return $resolved;
    }

    protected function getPrimaryKeyColumns($table): array
    {
        $cols = $this->sqlite->select("PRAGMA table_info(\"$table\")");
        $pks = [];
        foreach ($cols as $col) {
            if ($col->pk > 0) {
                $pks[] = ['name' => $col->name, 'pos' => $col->pk];
            }
        }
        usort($pks, fn($a, $b) => $a['pos'] <=> $b['pos']);
        return array_column($pks, 'name');
    }

    protected function getRowIdentifier($row, $pkColumns): string
    {
        if (empty($pkColumns)) {
            return 'ROW_NO_PK';
        }
        $parts = [];
        foreach ($pkColumns as $pk) {
            $parts[] = $pk . '=' . ($row->$pk ?? 'NULL');
        }
        return implode(', ', $parts);
    }

    protected function getPostgresColumnMetadata($table): array
    {
        $columns = $this->pgsql->select("
            SELECT 
                column_name, 
                data_type, 
                udt_name, 
                is_nullable, 
                character_maximum_length, 
                numeric_precision, 
                numeric_scale, 
                column_default 
            FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = ?
        ", [$table]);

        $map = [];
        foreach ($columns as $col) {
            $map[$col->column_name] = (array) $col;
        }
        return $map;
    }

    protected function migrateTable($table)
    {
        $sqliteCount = $this->sqlite->table($table)->count();
        if ($sqliteCount === 0) {
            $this->info("$table: 0 rows [SKIPPED - EMPTY]");
            return;
        }

        $this->info("Migrating $table (SQLite rows: $sqliteCount)...");

        $pgColMap = $this->getPostgresColumnMetadata($table);
        $enums = $this->getPostgresEnums($table);
        $uniqueIndexes = $this->getPostgresUniqueIndexes($table);
        $pkColumns = $this->getPrimaryKeyColumns($table);

        $this->checkUniqueConstraints($table, $uniqueIndexes);
        
        $query = $this->sqlite->table($table);
        
        if (!empty($pkColumns)) {
            foreach ($pkColumns as $pk) {
                $query->orderBy($pk);
            }
        } else {
            $allCols = $this->sqlite->select("PRAGMA table_info(\"$table\")");
            foreach ($allCols as $col) {
                $query->orderBy($col->name);
            }
        }
        
        $query->chunk(500, function ($rows) use ($table, $pgColMap, $enums, $pkColumns) {
            $insertData = [];
            
            foreach ($rows as $row) {
                $rowArray = (array) $row;
                $sanitizedRow = [];
                $rowIdentifier = $this->getRowIdentifier($row, $pkColumns);

                foreach ($rowArray as $col => $value) {
                    if (!isset($pgColMap[$col])) continue;

                    if (isset($this->deferredUpdates[$table]) && in_array($col, $this->deferredUpdates[$table])) {
                        continue;
                    }

                    $sanitizedRow[$col] = $this->validateAndConvert(
                        $table,
                        $rowIdentifier,
                        $col,
                        $value,
                        $pgColMap[$col],
                        $enums[$col] ?? null
                    );
                }
                $insertData[] = $sanitizedRow;
            }

            $this->pgsql->table($table)->insert($insertData);
        });
    }

    protected function processDeferredUpdates()
    {
        if (empty($this->deferredUpdates)) {
            return;
        }

        $this->info("\n--- Phase 2: Processing Deferred Circular Dependencies ---");

        foreach ($this->deferredUpdates as $table => $cols) {
            $this->info("Updating deferred columns for $table: " . implode(', ', $cols));
            
            $pgColMap = $this->getPostgresColumnMetadata($table);
            $enums = $this->getPostgresEnums($table);
            $pkColumns = $this->getPrimaryKeyColumns($table);

            if (empty($pkColumns)) {
                $this->error("Cannot perform deferred updates on $table without a primary key.");
                exit(1);
            }

            $query = $this->sqlite->table($table);
            
            $query->where(function($q) use ($cols) {
                foreach ($cols as $col) {
                    $q->orWhereNotNull($col);
                }
            });

            foreach ($pkColumns as $pk) {
                $query->orderBy($pk);
            }

            $query->chunk(500, function ($rows) use ($table, $cols, $pkColumns, $pgColMap, $enums) {
                foreach ($rows as $row) {
                    $rowArray = (array) $row;
                    $rowIdentifier = $this->getRowIdentifier($row, $pkColumns);
                    $updateData = [];

                    foreach ($cols as $col) {
                        $value = $rowArray[$col] ?? null;
                        if (is_null($value)) continue;

                        $updateData[$col] = $this->validateAndConvert(
                            $table,
                            $rowIdentifier,
                            $col,
                            $value,
                            $pgColMap[$col],
                            $enums[$col] ?? null
                        );
                    }

                    if (!empty($updateData)) {
                        $pgQuery = $this->pgsql->table($table);
                        foreach ($pkColumns as $pk) {
                            $pgQuery->where($pk, $rowArray[$pk]);
                        }
                        $pgQuery->update($updateData);
                    }
                }
            });
        }
    }

    protected function validateAndConvert($table, $rowIdentifier, $col, $value, $pgDef, $enumValues)
    {
        $isNullable = strtoupper($pgDef['is_nullable']) === 'YES';
        
        if (is_null($value)) {
            if (!$isNullable) {
                $this->haltMigration($table, $rowIdentifier, $col, $value, "Column is NOT NULL but SQLite value is NULL.");
            }
            return null;
        }

        $type = strtolower($pgDef['data_type']);
        $udt = strtolower($pgDef['udt_name']);

        // UUID check
        if ($udt === 'uuid') {
            if ($value === '') {
                if ($isNullable) return null;
                $this->haltMigration($table, $rowIdentifier, $col, "''", "Empty string UUID invalid for NOT NULL column.");
            }
            if (!preg_match('/^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i', $value)) {
                $this->haltMigration($table, $rowIdentifier, $col, $value, "Invalid UUID format.");
            }
            return $value;
        }

        // Boolean check
        if ($type === 'boolean' || $udt === 'bool') {
            if ($value === 1 || $value === '1' || strtolower((string)$value) === 'true') return true;
            if ($value === 0 || $value === '0' || strtolower((string)$value) === 'false') return false;
            $this->haltMigration($table, $rowIdentifier, $col, $value, "Cannot safely cast to boolean.");
        }

        // JSON check
        if ($type === 'json' || $type === 'jsonb' || $udt === 'json' || $udt === 'jsonb') {
            json_decode($value, true);
            if (json_last_error() !== JSON_ERROR_NONE) {
                $this->haltMigration($table, $rowIdentifier, $col, $value, "Malformed JSON: " . json_last_error_msg());
            }
            return $value;
        }

        // Enum check
        if ($type === 'USER-DEFINED' && $enumValues) {
            if (!in_array($value, $enumValues)) {
                $this->haltMigration($table, $rowIdentifier, $col, $value, "Value not in PostgreSQL Enum [" . implode(',', $enumValues) . "].");
            }
        }

        // String length check
        if (in_array($type, ['character varying', 'varchar']) && !is_null($pgDef['character_maximum_length'])) {
            $maxLength = (int) $pgDef['character_maximum_length'];
            if (strlen((string) $value) > $maxLength) {
                $this->haltMigration($table, $rowIdentifier, $col, $value, "String length exceeds PostgreSQL limit ($maxLength).");
            }
        }

        // Foreign Key Validation (Orphans)
        if (str_ends_with($col, '_id')) {
            $fks = $this->sqlite->select("PRAGMA foreign_key_list(\"$table\")");
            foreach ($fks as $fk) {
                if ($fk->from === $col) {
                    $parentExists = $this->sqlite->table($fk->table)->where($fk->to, $value)->exists();
                    if (!$parentExists) {
                        $this->haltMigration($table, $rowIdentifier, $col, $value, "Orphaned foreign key. Parent record missing in {$fk->table}.");
                    }
                }
            }
        }

        return $value;
    }

    protected function checkUniqueConstraints($table, $uniqueIndexes)
    {
        foreach ($uniqueIndexes as $index) {
            $cols = implode(', ', $index);
            
            $whereNotNulls = [];
            foreach ($index as $col) {
                $whereNotNulls[] = "$col IS NOT NULL";
            }
            $whereClause = implode(' AND ', $whereNotNulls);

            $duplicates = $this->sqlite->select("
                SELECT $cols, COUNT(*) as c 
                FROM $table 
                WHERE $whereClause
                GROUP BY $cols 
                HAVING c > 1
            ");

            if (count($duplicates) > 0) {
                $this->error("STOPPING: Duplicate values found in SQLite for unique constraint ($cols) on table $table.");
                exit(1);
            }
        }
    }

    protected function getPostgresEnums($table): array
    {
        $enums = [];
        $cols = $this->pgsql->select("
            SELECT column_name, udt_name 
            FROM information_schema.columns 
            WHERE table_name = ? AND data_type = 'USER-DEFINED'
        ", [$table]);

        foreach ($cols as $col) {
            $values = $this->pgsql->select("
                SELECT e.enumlabel 
                FROM pg_enum e 
                JOIN pg_type t ON e.enumtypid = t.oid 
                WHERE t.typname = ?
            ", [$col->udt_name]);
            
            $enums[$col->column_name] = array_column($values, 'enumlabel');
        }
        return $enums;
    }

    protected function getPostgresUniqueIndexes($table): array
    {
        $indexes = $this->sqlite->select("PRAGMA index_list(\"$table\")");
        $uniques = [];
        foreach ($indexes as $index) {
            if ($index->unique && strpos($index->name, 'autoindex') === false) {
                $idxCols = $this->sqlite->select("PRAGMA index_info(\"{$index->name}\")");
                $uniques[] = array_column($idxCols, 'name');
            }
        }
        return $uniques;
    }

    protected function resetSequences($orderedTables)
    {
        foreach ($orderedTables as $table) {
            if (in_array($table, $this->skipTables)) continue;
            
            $cols = $this->getPostgresColumnMetadata($table);
            foreach ($cols as $colName => $colDef) {
                if (!empty($colDef['column_default']) && str_contains($colDef['column_default'], 'nextval')) {
                    $this->info("Resetting sequence for $table.$colName...");
                    $this->pgsql->statement("SELECT setval(pg_get_serial_sequence('$table', '$colName'), COALESCE(MAX($colName), 0) + 1, false) FROM $table;");
                }
            }
        }
    }

    protected function verifyMigration($tables)
    {
        $this->info("Verifying migration...");
        foreach ($tables as $table) {
            if (in_array($table, $this->skipTables)) continue;

            $sqliteCount = $this->sqlite->table($table)->count();
            if ($sqliteCount === 0) continue;
            
            $pgCount = $this->pgsql->table($table)->count();

            if ($sqliteCount !== $pgCount) {
                $this->error("VERIFICATION FAILED: $table count mismatch. SQLite: $sqliteCount, PG: $pgCount");
            } else {
                $this->line("$table: $sqliteCount rows [OK]");
            }
        }
    }

    protected function haltMigration($table, $rowIdentifier, $column, $value, $problem)
    {
        $this->error("\nFAILED");
        $this->error("Table: $table");
        $this->error("Row Identifier: $rowIdentifier");
        $this->error("Column: $column");
        $this->error("SQLite value: " . print_r($value, true));
        $this->error("Error: $problem");
        throw new Exception("Migration validation failed on $table.$column.");
    }
}

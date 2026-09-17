<?php

namespace App\Http\Controllers\Api\SuperAdmin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\City;
use App\Models\Salon;
use App\Models\SubArea;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * SuperAdmin's control of the locality list.
 *
 * The list has to stay clean or everything built on it stops working. Two
 * spellings of the same neighbourhood split it in half: half the salons in
 * "Kothrud" and half in "kothrud", a collaborator matched to one and blind to
 * the other. So there is exactly one way to add a locality, it is here, and the
 * database refuses duplicates within a city.
 *
 * Deleting is deliberately hard. A locality with salons or people attached is
 * deactivated instead — it disappears from every dropdown but the records that
 * point at it keep meaning something.
 */
class SubAreaController extends Controller
{
    /** Every city that has localities, plus the ones that do not, for adding. */
    public function index(Request $request)
    {
        $request->validate([
            'city_id' => 'nullable|uuid|exists:cities,id',
            'search' => 'nullable|string|max:80',
        ]);

        $query = SubArea::with('city:id,name,state')
            ->withCount([
                'salons',
                'users',
            ]);

        if ($request->filled('city_id')) {
            $query->where('city_id', $request->city_id);
        }

        if ($request->filled('search')) {
            $term = "%{$request->search}%";
            $query->where(fn ($q) => $q->where('name', 'like', $term)
                ->orWhereHas('city', fn ($c) => $c->where('name', 'like', $term)));
        }

        $areas = $query->get()->sortBy([
            fn ($a, $b) => strcmp($a->city->name ?? '', $b->city->name ?? ''),
            fn ($a, $b) => strcmp($a->name, $b->name),
        ])->values();

        return response()->json([
            'success' => true,
            'data' => $areas->map(fn (SubArea $area) => [
                'id' => $area->id,
                'name' => $area->name,
                'is_active' => $area->is_active,
                'city_id' => $area->city_id,
                'city_name' => $area->city->name ?? '—',
                'state' => $area->city->state ?? null,
                'salon_count' => $area->salons_count,
                'people_count' => $area->users_count,
                // What stops it being deleted outright.
                'in_use' => $area->salons_count > 0 || $area->users_count > 0,
            ]),
            // Only cities that are switched on — offering a disabled city would
            // create localities nobody can ever pick.
            'cities' => City::where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'name', 'state']),
            'summary' => [
                'total' => SubArea::count(),
                'cities_covered' => SubArea::distinct('city_id')->count('city_id'),
            ],
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'city_id' => 'required|uuid|exists:cities,id',
            'name' => [
                'required', 'string', 'max:120',
                Rule::unique('sub_areas')->where(fn ($q) => $q->where('city_id', $request->city_id)),
            ],
        ]);

        $area = SubArea::create($data + ['is_active' => true]);

        return response()->json([
            'success' => true,
            'message' => "{$area->name} added.",
            'data' => $area->load('city:id,name'),
        ], 201);
    }

    /**
     * Take a spreadsheet's worth of localities at once.
     *
     * Runs in two passes and the first one writes nothing. A bulk insert into
     * the table that every address on the platform points at is not something
     * to find out about afterwards, so the same request that would import the
     * rows will instead describe what it is about to do, row by row, and wait
     * to be asked again with commit set.
     *
     * Nothing here rejects a whole upload over one bad line. A file of two
     * hundred localities with three typos in it is a file worth importing a
     * hundred and ninety-seven of, and the three are named so they can be
     * fixed. The only outright failures are a file so large it looks like a
     * mistake, and values too long to be a locality name at all.
     */
    public function import(Request $request)
    {
        $data = $request->validate([
            'rows' => 'required|array|min:1|max:2000',
            // Deliberately permissive. Everything a row could be wrong about is
            // reported against that row instead of failing the request, so the
            // only job of this validation is to bound the input.
            'rows.*.city' => 'nullable|string|max:255',
            'rows.*.state' => 'nullable|string|max:255',
            'rows.*.area' => 'nullable|string|max:255',
            'rows.*.line' => 'nullable|integer',
            'commit' => 'sometimes|boolean',
        ]);

        $cities = City::get(['id', 'name', 'state']);

        // Two ways in, because a file may or may not name the state. Pune is
        // unambiguous; there is a Hamirpur in two of them.
        $byName = [];
        $byNameAndState = [];
        foreach ($cities as $city) {
            $name = self::key($city->name);
            $byName[$name][] = $city;
            $byNameAndState[$name.'|'.self::key((string) $city->state)] = $city;
        }

        // Case-folded, because the duplicate this is guarding against is
        // "Kothrud" arriving next to "kothrud". MySQL would refuse the second
        // one and SQLite would accept it; neither outcome should depend on
        // which database is underneath.
        $existing = [];
        foreach (SubArea::get(['city_id', 'name']) as $area) {
            $existing[$area->city_id.'|'.self::key($area->name)] = true;
        }

        $seen = [];
        $report = [];
        $create = [];

        foreach ($data['rows'] as $index => $row) {
            $line = $row['line'] ?? $index + 1;
            $cityName = trim((string) ($row['city'] ?? ''));
            $stateName = trim((string) ($row['state'] ?? ''));
            $areaName = trim((string) ($row['area'] ?? ''));

            $entry = [
                'line' => $line,
                'city' => $cityName,
                'state' => $stateName,
                'area' => $areaName,
            ];

            if ($cityName === '' || $areaName === '') {
                $report[] = $entry + [
                    'status' => 'invalid',
                    'message' => $areaName === '' ? 'No area name.' : 'No city.',
                ];

                continue;
            }

            if (mb_strlen($areaName) > 120) {
                $report[] = $entry + ['status' => 'invalid', 'message' => 'Area name is over 120 characters.'];

                continue;
            }

            $cityKey = self::key($cityName);
            $city = null;

            if ($stateName !== '') {
                $city = $byNameAndState[$cityKey.'|'.self::key($stateName)] ?? null;

                // Named a state the city is not in. Worth saying so plainly —
                // it is usually a typo in the state, not an unknown city.
                if (! $city && isset($byName[$cityKey])) {
                    $report[] = $entry + [
                        'status' => 'unknown_city',
                        'message' => sprintf(
                            '%s is not in %s. Known: %s.',
                            $cityName,
                            $stateName,
                            collect($byName[$cityKey])->pluck('state')->filter()->implode(', ')
                        ),
                    ];

                    continue;
                }
            } elseif (isset($byName[$cityKey])) {
                $matches = $byName[$cityKey];

                // Unreachable while cities.name carries a UNIQUE index, and
                // kept for the day it does not: India has a Hamirpur in two
                // states, so that index cannot survive a full city list. When
                // it goes, this refuses to guess rather than silently picking
                // whichever row came back first.
                if (count($matches) > 1) {
                    $report[] = $entry + [
                        'status' => 'ambiguous_city',
                        'message' => sprintf(
                            'There is a %s in %s. Add a state column to say which.',
                            $cityName,
                            collect($matches)->pluck('state')->filter()->implode(' and ')
                        ),
                    ];

                    continue;
                }

                $city = $matches[0];
            }

            if (! $city) {
                $report[] = $entry + [
                    'status' => 'unknown_city',
                    'message' => "No city called {$cityName}. Cities are not created by this import.",
                ];

                continue;
            }

            $areaKey = $city->id.'|'.self::key($areaName);

            if (isset($existing[$areaKey])) {
                $report[] = $entry + [
                    'status' => 'duplicate',
                    'message' => "{$city->name} already has this area.",
                ];

                continue;
            }

            // The same locality twice in one file. The first one stands.
            if (isset($seen[$areaKey])) {
                $report[] = $entry + [
                    'status' => 'repeated',
                    'message' => "Already on line {$seen[$areaKey]} of this file.",
                ];

                continue;
            }

            $seen[$areaKey] = $line;
            $create[] = ['city_id' => $city->id, 'name' => $areaName];

            $report[] = $entry + [
                'status' => 'ready',
                'message' => "Will be added to {$city->name}.",
                'resolved_city' => $city->name.($city->state ? ", {$city->state}" : ''),
            ];
        }

        $summary = [
            'total' => count($report),
            'ready' => count($create),
            'duplicate' => self::countOf($report, 'duplicate'),
            'repeated' => self::countOf($report, 'repeated'),
            'unknown_city' => self::countOf($report, 'unknown_city'),
            'ambiguous_city' => self::countOf($report, 'ambiguous_city'),
            'invalid' => self::countOf($report, 'invalid'),
        ];

        // The look-before-you-leap pass, and where every request stops unless
        // it was sent back a second time with commit.
        if (! $request->boolean('commit')) {
            return response()->json([
                'success' => true,
                'committed' => false,
                'summary' => $summary,
                'rows' => $report,
            ]);
        }

        if ($create === []) {
            return response()->json([
                'success' => false,
                'committed' => false,
                'summary' => $summary,
                'rows' => $report,
                'message' => 'Nothing in that file can be added.',
            ], 422);
        }

        DB::transaction(function () use ($create) {
            foreach ($create as $row) {
                SubArea::create($row + ['is_active' => true]);
            }
        });

        AuditLogger::record(
            AuditLog::SUB_AREAS_IMPORTED,
            null,
            sprintf('%d areas across %d cities', count($create), count(array_unique(array_column($create, 'city_id')))),
            null,
            null,
            [
                'created' => count($create),
                'summary' => $summary,
                // Enough to recognise the import later without storing the file.
                'sample' => array_slice(array_column($create, 'name'), 0, 20),
            ]
        );

        return response()->json([
            'success' => true,
            'committed' => true,
            'created' => count($create),
            'summary' => $summary,
            'rows' => $report,
            'message' => sprintf('%d area%s added.', count($create), count($create) === 1 ? '' : 's'),
        ]);
    }

    /** Case- and space-insensitive, for comparing names people typed. */
    private static function key(string $value): string
    {
        return mb_strtolower(preg_replace('/\s+/u', ' ', trim($value)));
    }

    private static function countOf(array $report, string $status): int
    {
        return count(array_filter($report, fn ($row) => $row['status'] === $status));
    }

    public function update(Request $request, string $id)
    {
        $area = SubArea::find($id);

        if (! $area) {
            return response()->json(['success' => false, 'message' => 'Sub-area not found.'], 404);
        }

        $data = $request->validate([
            'name' => [
                'sometimes', 'string', 'max:120',
                Rule::unique('sub_areas')
                    ->where(fn ($q) => $q->where('city_id', $area->city_id))
                    ->ignore($area->id),
            ],
            'is_active' => 'sometimes|boolean',
        ]);

        $area->update($data);

        return response()->json([
            'success' => true,
            'message' => 'Sub-area updated.',
            'data' => $area->fresh()->load('city:id,name'),
        ]);
    }

    /**
     * Remove a locality nobody is standing in.
     *
     * Anything with salons or people attached is switched off instead: deleting
     * it would orphan their addresses, and an address that used to say
     * "Kothrud" and now says nothing is worse than one nobody can newly choose.
     */
    public function destroy(string $id)
    {
        $area = SubArea::find($id);

        if (! $area) {
            return response()->json(['success' => false, 'message' => 'Sub-area not found.'], 404);
        }

        $salons = Salon::where('sub_area_id', $area->id)->count();
        $people = User::where('sub_area_id', $area->id)->count();

        if ($salons > 0 || $people > 0) {
            $area->update(['is_active' => false]);

            return response()->json([
                'success' => true,
                'deactivated' => true,
                'message' => sprintf(
                    '%s is used by %d salon(s) and %d person/people, so it has been switched off rather than deleted. It will no longer appear in any dropdown.',
                    $area->name,
                    $salons,
                    $people
                ),
            ]);
        }

        $name = $area->name;
        $area->delete();

        return response()->json([
            'success' => true,
            'deactivated' => false,
            'message' => "{$name} deleted.",
        ]);
    }
}

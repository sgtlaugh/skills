# owlpost

Records owl sightings and serves them over a tiny API.

- `SightingStore.add(species, count, seen_at)` saves one sighting.
- `SightingStore.list(limit)` returns the newest sightings first.
- `api.list_sightings`, `api.species_summary` and `api.export` back the three endpoints.

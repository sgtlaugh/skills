**Review: PR #812 - OWL-4521: Retry moon-phase fetches and cache the result per hour**
**Author**: @ada | **Base**: main <- OWL-4521 | **Files**: 4 changed (+96, -12)
**CI**: passing | **Reviewers**: @rhs
**Filtered**: 0 files skipped | **Conventions**: CLAUDE.md (8 rules) | **Existing comments**: 2 fetched (1 deduped) | **JIRA**: OWL-4521 fetched
**Verified**: 5 claims via darkmoon - 3 upheld, 1 weak, 0 can't-determine, 1 refuted

---

**What this PR does:** Wraps the moon-phase API call in a retry loop and caches the parsed phase per hour, so the sighting page stops timing out when the upstream is slow.

**Findings summary**

🛑  #1  owl/moon.py:88
    The retry loop holds the cache lock across the HTTP call, so one slow upstream stalls every reader

⚠️  #2  owl/moon.py:61
    Retries on 4xx too, so a bad API key burns three calls per request

⚠️  #3  owl/cache.py:14
    Hour bucket uses local time, so readers in two zones miss each other's cache

✏️  #4  owl/moon.py:40 (pre-existing)
    `MOON_URL` is built with string concatenation instead of `urljoin`

---

🛑  **#1 · critical · Bug · owl/moon.py:88**

**Problem:** `refresh_moon_cache` takes `_lock` before calling `fetch_phase`, which now retries up to three times with a 10s timeout.
**Impact:** One slow upstream blocks every page that reads the cache for up to 30s, which is an outage of the sighting page.

**Fix:**

```python
phase = fetch_phase()
with _lock:
    _cache[hour] = phase
```

*Confirmed - read moon.py:80-95 and the timeout in client.py:12.* (verified)

---

⚠️  **#2 · warning · Bug · owl/moon.py:61**

**Problem:** The retry predicate is `status >= 400`, so a 401 is retried like a 503.
**Impact:** A revoked key triples the call volume against a rate-limited API before the error surfaces.

**Fix:**

```python
if status >= 500 or status == 429:
    continue
```

*Confirmed - read moon.py:55-70.* (verified)

---

⚠️  **#3 · warning · Bug · owl/cache.py:14**

**Problem:** `hour_key` uses `datetime.now()` without a timezone.
**Impact:** Two workers in different zones write separate keys for the same hour, so the cache hit rate halves.

**Fix:**

```python
hour_key = datetime.now(timezone.utc).strftime("%Y%m%d%H")
```

*Inferred - would need the worker deployment config to confirm the zones differ.* (weak)

---

✏️  **#4 · nit · Refactor · owl/moon.py:40 · pre-existing**

`MOON_URL` is built with `+`; `urljoin` handles the trailing slash. Not part of this diff.

*Confirmed - read moon.py:40.* (verified)

---

**Independent Review Lenses:** saboteur raised #1; operator: no findings; others folded into #2 and #3.

---

**Summary**

The retry is the right fix, but it holds the cache lock across the network call (#1), which turns a slow upstream into an outage. Not examined: the deploy config behind #3.

**Recommendation:** ❌ Request Changes
**Reason:** #1 can take the sighting page down.
**Confidence:** High - traced the lock and the timeout; darkmoon verified #1 and #2.

---

**Time taken**: 3m 12s

---
name: jira
description: Create, search, and manage JIRA tickets and fetch/edit Confluence pages via REST API
trigger: /jira
allowed-tools: Read, Bash(curl:*), Bash(jq:*), Bash(grep:*), Bash(pandoc:*), Bash(printf:*), Bash(head:*), Bash(git branch:*), Bash(cp:*), Bash(python3:*), Bash(echo:*), Bash(command:*)
---

# JIRA Ticket Management

Create, search, and manage JIRA tickets via REST API.

## Setup

Credentials live in a JSON file - `$CLAUDE_SKILLS_CREDENTIALS`, default `~/.config/claude-skills/credentials.json` - with `jiraBaseUrl` (e.g. `https://acme.atlassian.net`), `jiraEmail` and `jiraApiToken` (an Atlassian API token). Shell state does not persist between tool calls. Prepend this to EVERY bash call that hits the API:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
JIRA_URL=$(jq -r '.jiraBaseUrl // error("jiraBaseUrl unset in the credentials file")' "$C") || exit 1
JIRA_B64=$(jq -r 'if .jiraEmail and .jiraApiToken then "\(.jiraEmail):\(.jiraApiToken)" | @base64 else error("jiraEmail/jiraApiToken unset in the credentials file") end' "$C") || exit 1
```

**Important:** Use inline `-H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json"` directly in each curl call. Do NOT use bash arrays (`JIRA_AUTH=(...)` / `"${JIRA_AUTH[@]}"`) - zsh breaks array expansion in complex commands.

Every call uses `-sS --fail-with-body`: an HTTP error prints `curl: (22)` on stderr and still prints Jira's JSON body. **Any `curl: (N)` line on stderr means that call failed** (22 = HTTP error, 6/7 = host unreachable) - in a pipe the exit code is the last command's, so the stderr line is the signal. Report the `errorMessages`/`errors` from the body; presenting a failed call as created/updated/found/empty is WRONG.

## Usage

```
/jira PROJ-123                    # get ticket details
/jira search "auth timeout"       # search tickets (free text → JQL)
/jira create PROJ                 # create ticket in project
/jira assign PROJ-123             # assign ticket to self
/jira comment PROJ-123            # add comment
/jira transition PROJ-123         # change ticket status
/jira confluence <url|id>         # fetch Confluence page (see Confluence section)
```

**Every write needs a yes.** Create, update, assign, transition, comment and Confluence PUT all show the user a readable preview first (summary, fields, and descriptions or comments rendered as markdown - ADF JSON is unreadable; for a page, the checklist counts) and wait for an explicit yes in their reply. A write without a shown preview and a yes is WRONG, including when another skill asked for it.

## Operations

### Search Tickets (JQL)
```bash
jq -n --arg jql 'project = PROJ AND assignee = currentUser() ORDER BY updated DESC' \
  '{jql: $jql, maxResults: 10, fields: ["summary", "status", "assignee", "issuetype", "priority", "updated"]}' \
| curl -sS --fail-with-body -X POST "$JIRA_URL/rest/api/3/search/jql" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" -d @-
```

**Natural language → JQL translation:**

| User says | JQL |
|-----------|-----|
| "my open bugs" | `assignee = currentUser() AND issuetype = Bug AND statusCategory != Done` |
| "unassigned PROJ tickets" | `project = PROJ AND assignee is EMPTY AND statusCategory != Done` |
| "what I worked on this week" | `assignee = currentUser() AND updated >= startOfWeek()` |
| "blockers in current sprint" | `project = PROJ AND sprint in openSprints() AND priority = "<the scheme's top level>"` (look it up - see Gotchas: names like "Highest" don't exist everywhere) |

### Get Ticket
```bash
curl -sS --fail-with-body "$JIRA_URL/rest/api/3/issue/PROJ-123?fields=summary,status,assignee,priority,description,comment,parent,labels,issuelinks" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json"
```
`parent.key` = epic/parent ticket; `issuelinks[]` = linked tickets (`.type.name` + `.inwardIssue.key` / `.outwardIssue.key`).

### Linked PRs (GitHub)
GitHub PRs are NOT in `issuelinks` or `/remotelink` here - the GitHub integration reports them through the dev-status API, keyed by the numeric issue id and the integration's instance type:
```bash
ID=$(curl -sS --fail-with-body "$JIRA_URL/rest/api/3/issue/PROJ-123?fields=summary" -H "Authorization: Basic $JIRA_B64" | jq -r .id)
APP=$(curl -sS --fail-with-body "$JIRA_URL/rest/dev-status/latest/issue/summary?issueId=$ID" -H "Authorization: Basic $JIRA_B64" \
  | jq -r '.summary.pullrequest.byInstanceType | keys[0] // empty')
if [ -n "$APP" ]; then curl -sS --fail-with-body "$JIRA_URL/rest/dev-status/latest/issue/detail?issueId=$ID&applicationType=$APP&dataType=pullrequest" \
  -H "Authorization: Basic $JIRA_B64" | jq -r '.detail[].pullRequests[] | "\(.status)\t\(.url)\t\(.name)"'
else echo "dev-status: no linked PRs"; fi
```
Empty `APP` = no linked PRs **only if neither call printed `curl: (N)`** - a failed call also leaves `APP` empty, and that is `Can't-determine`, not "none". Verified on a Jira Cloud site with the GitHub for Jira app (instance type `oAuth-com.github.integration.production`); other integrations report a different key - the summary call discovers it. An empty answer is not proof either: one ticket with 6 merged PRs came back empty here, so also run `gh search prs "PROJ-123"` when completeness matters.

### Create Ticket
```bash
curl -sS --fail-with-body -X POST "$JIRA_URL/rest/api/3/issue" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "PROJ"},
      "summary": "Ticket title",
      "issuetype": {"name": "Task"},
      "description": {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Description here"}]}]}
    }
  }'
```

### Update Ticket
```bash
curl -sS --fail-with-body -X PUT "$JIRA_URL/rest/api/3/issue/PROJ-123" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  -d '{"fields": {"summary": "Updated title"}}'
```

### Assign Ticket
```bash
curl -sS --fail-with-body -X PUT "$JIRA_URL/rest/api/3/issue/PROJ-123/assignee" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  -d '{"accountId": "ACCOUNT_ID"}'
```
Get own accountId: `curl -sS --fail-with-body "$JIRA_URL/rest/api/3/myself" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" | jq -r .accountId`

### Transition Ticket (change status)
```bash
curl -sS --fail-with-body "$JIRA_URL/rest/api/3/issue/PROJ-123/transitions" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json"
curl -sS --fail-with-body -X POST "$JIRA_URL/rest/api/3/issue/PROJ-123/transitions" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  -d '{"transition": {"id": "TRANSITION_ID"}}'
```

### Formatting (ADF)
Descriptions and comments are Atlassian Document Format: a tree of nodes. **Markdown inside a `text` node renders literally** - ```` ``` ````, `**bold**` and `- item` show up as raw characters in Jira. Build the structure from nodes instead:
```json
{"type": "doc", "version": 1, "content": [
  {"type": "paragraph", "content": [
    {"type": "text", "text": "Root cause: ", "marks": [{"type": "strong"}]},
    {"type": "text", "text": "the retry loop in "},
    {"type": "text", "text": "worker.py", "marks": [{"type": "code"}]},
    {"type": "text", "text": " (permalink)", "marks": [{"type": "link", "attrs": {"href": "https://github.com/acme/owl-api/blob/<sha>/worker.py#L42"}}]}
  ]},
  {"type": "bulletList", "content": [
    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "First point"}]}]},
    {"type": "listItem", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Second point"}]}]}
  ]},
  {"type": "codeBlock", "attrs": {"language": "python"}, "content": [{"type": "text", "text": "for attempt in range(retries):\n    send()"}]}
]}
```
- **Code** → `codeBlock` node (multi-line, keeps newlines) or the `code` mark (inline). Never a fenced block inside a paragraph.
- **Lists** → `bulletList`/`orderedList` → `listItem` → `paragraph`. A `listItem` holding bare `text` is rejected.
- **Build the body with `jq -n --arg`** (or a Python dict) so quotes and newlines in code are escaped - hand-built JSON strings break on the first `"` in a snippet.

### Add Comment
Uses the same ADF format (see Formatting above).
```bash
curl -sS --fail-with-body -X POST "$JIRA_URL/rest/api/3/issue/PROJ-123/comment" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  -d '{"body": {"type": "doc", "version": 1, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Comment text"}]}]}}'
```

### List Projects
```bash
curl -sS --fail-with-body "$JIRA_URL/rest/api/3/project/search?maxResults=50" -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" | jq -r '.values[] | "\(.key): \(.name)"'
```

## Confluence

Same Atlassian instance, same auth. Confluence lives under `$JIRA_URL/wiki`. Reuse the Setup block (`$JIRA_B64`) - if JIRA auth works, Confluence does too (same token).

```
/jira confluence <page-url>       # fetch page as readable text + version metadata
/jira confluence <page-id>        # fetch by numeric page id
/jira confluence search "query"   # CQL text search
/jira confluence edit <page-url>  # edit a Confluence page (see Update a page)
```

### Fetch a page

Resolve the page id from a URL (`.../wiki/spaces/ENG/pages/123456789/Title`), a `pageId=` query, or a bare number:
```bash
PAGE="INPUT"
PAGE_ID=$(printf '%s' "$PAGE" | grep -oE 'pages/[0-9]+' | grep -oE '[0-9]+' | head -1)
[ -z "$PAGE_ID" ] && PAGE_ID=$(printf '%s' "$PAGE" | grep -oE 'pageId=[0-9]+' | grep -oE '[0-9]+' | head -1)
printf '%s' "$PAGE" | grep -qE '^[0-9]+$' && PAGE_ID="$PAGE"
```
Shell state does not persist between calls: once resolved, start every later Confluence block with `PAGE_ID=<the literal id>` alongside the auth lines - an empty `$PAGE_ID` hits `/content/` and fetches the wrong thing.

A tiny link (`/wiki/x/AbCdEf`) carries no numeric id - resolve the redirect and extract in the SAME call (a fresh call would reset `PAGE`): the extraction block above, with its first line replaced by
```bash
PAGE=$(curl -sSIL --fail -o /dev/null -w '%{url_effective}' "<tiny link>" -H "Authorization: Basic $JIRA_B64")
```

Fetch content + metadata (`export_view` = clean rendered HTML; `version` for stamping which revision was read):
```bash
curl -sS --fail-with-body "$JIRA_URL/wiki/rest/api/content/$PAGE_ID?expand=body.export_view,version,space" \
  -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" > /tmp/conf_$PAGE_ID.json
```

Metadata + body:
```bash
jq -r '"# \(.title)\nSpace \(.space.key) | Version \(.version.number) (\(.version.when)) | ID \(.id)"' /tmp/conf_$PAGE_ID.json
jq -r '.body.export_view.value' /tmp/conf_$PAGE_ID.json > /tmp/conf_$PAGE_ID.html
```

Convert HTML → markdown. Prefer `pandoc`; if absent, read the `.html` file directly (Claude parses HTML natively):
```bash
command -v pandoc >/dev/null && pandoc -f html -t gfm /tmp/conf_$PAGE_ID.html || echo "no pandoc - read /tmp/conf_$PAGE_ID.html"
```

**Always report the version number + date.** Downstream reviews (e.g. `/gadfly`) stamp which revision they read - a spec moves, a stale review misleads.

### List attachments (diagrams, images)

Specs hide design in diagrams. List attachments so they are not silently missed:
```bash
curl -sS --fail-with-body "$JIRA_URL/wiki/rest/api/content/$PAGE_ID/child/attachment?expand=version" \
  -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" \
  | jq -r '.results[] | "\(.title) [\(.metadata.mediaType)] \(._links.download)"'
```
Download links are relative to `$JIRA_URL/wiki`. Fetch one: `curl -sS --fail-with-body -L "$JIRA_URL/wiki<download-link>" -H "Authorization: Basic $JIRA_B64" -o <file>`.

### CQL search

Use `--get --data-urlencode` so multi-word / special-char queries encode correctly (a raw `?cql=...` breaks on spaces and quotes):
```bash
curl -sS --fail-with-body --get "$JIRA_URL/wiki/rest/api/content/search" \
  --data-urlencode 'cql=text~"QUERY"' --data-urlencode 'limit=10' \
  -H "Authorization: Basic $JIRA_B64" \
  | jq -r '.results[] | "\(.id)  \(.title)"'
```

### Update a page

Confluence pages are stored as XHTML-like "storage format." Editing requires surgical HTML manipulation.

**Fetch for editing** - use `body.storage` (not `body.export_view` which is read-only rendered HTML):
```bash
curl -sS --fail-with-body "$JIRA_URL/wiki/rest/api/content/$PAGE_ID?expand=body.storage,version" \
  -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" > /tmp/conf_$PAGE_ID.json
jq -r '.body.storage.value' /tmp/conf_$PAGE_ID.json > /tmp/conf_${PAGE_ID}_edit.html
cp /tmp/conf_${PAGE_ID}_edit.html /tmp/conf_${PAGE_ID}_backup.html
```
The edit and backup files carry the page id: with a shared name, two sessions editing different pages overwrite each other and the PUT pushes the wrong page's body.

**Edit the HTML** using Python (not sed - HTML on one line, position-based edits corrupt). Use unique text anchors for replacements, never byte positions (earlier edits shift positions).

**Push the update** - the body is read from the file (a shell argument caps at 128 KiB, and long specs exceed it), and the title and next version come from the fetched page, so a forgotten placeholder can't rename the page:
```bash
jq -n --rawfile body /tmp/conf_${PAGE_ID}_edit.html --slurpfile p /tmp/conf_$PAGE_ID.json --arg msg "<what changed>" \
  '{version: {number: ($p[0].version.number + 1), message: $msg}, title: $p[0].title, type: "page",
    body: {storage: {value: $body, representation: "storage"}}}' \
| curl -sS --fail-with-body -X PUT "$JIRA_URL/wiki/rest/api/content/$PAGE_ID" \
    -H "Authorization: Basic $JIRA_B64" -H "Content-Type: application/json" -d @- \
| jq '{id: .id, version: .version.number}'
```

**Verification checklist (run before every push).** Counts for the backup and the edit, side by side:
```bash
python3 - "$PAGE_ID" <<'EOF'
import re, sys
for side in ("backup", "edit"):
    s = open(f"/tmp/conf_{sys.argv[1]}_{side}.html").read()
    tags = {t: len(re.findall(rf"<{t}[ >]", s)) for t in ("table", "tbody", "tr", "td", "th", "div", "ul", "li")}
    print(side, tags, "cdata", s.count("<![CDATA["), "comment-markers", s.count("ac:inline-comment-marker"))
EOF
```
- TOC macro (`<ac:structured-macro ac:name="toc">`) byte-identical to original
- Tag balance preserved vs original for: table, tbody, tr, td, th, div, ul, li
- CDATA block count balanced (opens = closes)
- Inline comment markers (`ac:inline-comment-marker`) count unchanged
- All deletion targets gone, all addition targets present
- Unchanged content spot-check passed

**Storage format gotchas:**
- HTML is one giant line. Heading `local-id` attributes differ between `export_view` and `storage` format - always fetch `body.storage` for edits.
- Code blocks use `<ac:structured-macro ac:name="code">` with `<ac:plain-text-body><![CDATA[...]]></ac:plain-text-body>`, not `<pre>` tags.
- Tables: `<div class="table-wrap"><table data-table-width="760" data-layout="default"><tbody>...</tbody></table></div>`
- Info/note boxes: `<div class="confluence-information-macro confluence-information-macro-note">` with nested `<div class="confluence-information-macro-body">`
- Inline comments: `<ac:inline-comment-marker ac:ref="UUID">text</ac:inline-comment-marker>` - preserve these or comments are orphaned.
- `<p>` tags are often unclosed in Confluence storage format. Compare tag balance against original, not against zero.
- 409 Conflict on PUT = someone edited between your fetch and push. Re-fetch, check current version, rebase edits.

### Confluence error codes
401 auth, 403 no page permission, 404 page not found, 409 version conflict (re-fetch and retry with correct version number). If JIRA works but Confluence 401s, the token lacks Confluence scope (rare - Atlassian Cloud tokens usually cover both).

## Response Handling

- After creation: `jq -r '.key'` then show `$JIRA_URL/browse/KEY`
- Errors: `jq -r '.errors // .errorMessages'`
- HTTP codes: 201 created, 204 updated, 400 bad request, 401 auth failed, 404 not found

## Guidelines

- Infer project key from git branch (e.g. a `PROJ-123-fix-login` branch = `PROJ` project)
- When creating: ask for summary, type (Task/Bug/Story), priority, and description
- Show ticket URL after creation
- `Bash(python3:*)` is granted for Confluence HTML edits and can run anything, so the yes-before-write rule above is the real boundary, not the grant list
- Display responses in readable format, not raw JSON

## Gotchas

- **Priority schemes vary per project.** Don't use the global `/rest/api/3/priority` list, and don't read one ticket's priority - that shows one value, not the scheme. List the priorities the project's create screen allows for the issue type:
  ```bash
  TYPE_ID=$(curl -sS --fail-with-body "$JIRA_URL/rest/api/3/issue/createmeta/PROJ/issuetypes" -H "Authorization: Basic $JIRA_B64" \
    | jq -r '(.issueTypes // .values)[] | select(.name == "Bug") | .id')
  curl -sS --fail-with-body "$JIRA_URL/rest/api/3/issue/createmeta/PROJ/issuetypes/$TYPE_ID?maxResults=100" -H "Authorization: Basic $JIRA_B64" \
    | jq -r '(.fields // .values)[] | select(.fieldId == "priority") | .allowedValues[] | "\(.id)\t\(.name)"'
  ```
  The list comes back **unordered** (one real scheme returned Level 4, 1, 2, 3). Rank by the number or severity word in each name; if the names carry neither, ask the user which is highest - never assume array order or names like "P4"/"Normal".

- **Sprint assignment may fail.** Moving tickets via `/rest/agile/1.0/sprint/{id}/issue` can hit permission errors. Create ticket first, attempt sprint move, tell user to drag manually if it fails.

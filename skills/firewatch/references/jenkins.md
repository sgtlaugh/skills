# Failed Jenkins jobs - firewatch reference

Read by `/firewatch` for a failed Jenkins job alert; the catalog it names is `~/.config/claude-skills/services.md`.

CI/CD, not production. The job decides the stakes - the catalog's **Jenkins** section says what each job suffix blocks and how jobs are named.

Shell state does not persist between tool calls. Prepend this to EVERY bash call that hits Jenkins, with the catalog's Jenkins base URL written in literally:
```bash
C=${CLAUDE_SKILLS_CREDENTIALS:-$HOME/.config/claude-skills/credentials.json}
JENKINS_AUTH=$(jq -r 'if .jenkinsUser and .jenkinsApiToken then "\(.jenkinsUser):\(.jenkinsApiToken)" else error("jenkinsUser/jenkinsApiToken unset in the credentials file") end' "$C") || exit 1
J=<Jenkins base URL>
```
Pass `-g` whenever the URL has `tree=` - its `[]{}` are curl glob syntax otherwise (`curl: (3) bad range in URL`).

1. **History - the flaky verdict comes from here, not from one build:**
   ```bash
   curl -sS --fail-with-body -g -u "$JENKINS_AUTH" "$J/job/<job>/api/json?tree=builds[number,result,timestamp,actions[causes[shortDescription],parameters[name,value],lastBuiltRevision[SHA1]]]{0,8}" \
     | jq -r '.builds[] | [.number, (.result // "RUNNING"), (.timestamp/1000|todate),
         ([.actions[]?.parameters?[]? | select(.name=="ghprbActualCommit") | .value[:10]][0] // [.actions[]?.lastBuiltRevision?.SHA1? | select(.)][0][:10] // "-"),
         ([.actions[]?.causes?[]?.shortDescription] | join("; ") | .[:80])] | @tsv'
   ```
   For PR jobs, group rows by PR first - every PR has its own SHA, so unrelated PRs failing is not a pattern. Then apply the first matching row:

   | Pattern in the history | Verdict |
   |---|---|
   | Same commit SHA both passes and fails | **Flaky** |
   | Same SHA fails every time, including "Started by Naginator" auto-retries | **Deterministic** - the commit or its dependencies |
   | A single-branch job (catalog's *Single-branch jobs*) fails across several different SHAs | **Broken job/environment** (base image, registry, credentials) - not one commit's fault |
   | Fewer than 2 finished builds on any one SHA, or none of the above | **Can't-determine** - widen `{0,8}` to `{0,20}`; still unclear → report the gap, don't pick a verdict |
2. **Failure evidence** - most jobs publish no test report (`/testReport/api/json` → 404), so the console is the evidence:
   ```bash
   curl -sS --fail-with-body -u "$JENKINS_AUTH" "$J/job/<job>/<number>/consoleText" \
     | grep -nE '^ERROR|ERROR:|FAILED|Error:|Traceback|AssertionError|exit code|returned a non-zero|npm ERR|failed to solve' | tail -15
   ```
   Then read 30 lines from the first real hit (`<line>` = its number) for the cause, in a new call with the preamble:
   ```bash
   curl -sS --fail-with-body -u "$JENKINS_AUTH" "$J/job/<job>/<number>/consoleText" | tail -n +<line> | head -30
   ```
   Console text contains author emails - quote the error lines only.
3. **PR builds** (GitHub Pull Request Builder) carry `ghprbPullId`, `ghprbPullLink`, `ghprbActualCommit`, `ghprbPullAuthorLogin` in their parameters. Check the diff for test-breaking changes: `gh pr diff <ghprbPullId> --repo <github-org>/<repo>`.
4. **Act on the verdict:** flaky → ticket naming the job + builds; deterministic → put the PR author (`ghprbPullAuthorLogin`, or the "Started by GitHub push by <user>" cause) under **Requires Human** to notify; broken environment → ticket to the job owner (catalog's *Infra job owner* for infra jobs); Can't-determine → report the history you saw.

**Jenkins is read-only here** - GET only. Never `POST` to `/build`, `/rebuild`, `/stop` or `/doDelete`; re-running a job is a human action.

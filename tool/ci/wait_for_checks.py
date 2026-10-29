"""Block TestFlight delivery until every required check of the commit has passed.

The signing credentials must never be used for a commit whose required CI
checks failed, were cancelled or are still running, so the delivery workflow
polls the commit's check runs (read-only, no secrets) and fails closed.
"""
import json
import os
from pathlib import Path
import time
import urllib.request

REQUIRED = json.loads(Path(__file__).with_name('required_checks.json').read_text())['contexts']
PASSING = ('success', 'skipped', 'neutral')


def evaluate(check_runs, required=REQUIRED):
    """-> ('passed' | 'pending' | 'failed', [problem, ...]).

    The newest run of a context decides, so a re-run replaces an older failure.
    """
    newest = {}
    for run in check_runs:
        name = run.get('name')
        if name in required and run.get('id', 0) >= newest.get(name, {}).get('id', -1):
            newest[name] = run
    failed, pending = [], []
    for name in required:
        run = newest.get(name)
        if run is None or run.get('status') != 'completed':
            pending.append(f'{name}: not finished')
        elif run.get('conclusion') not in PASSING:
            failed.append(f"{name}: {run.get('conclusion')}")
    if failed:
        return 'failed', failed
    return ('pending', pending) if pending else ('passed', [])


def fetch(repository, sha, token):
    runs, page = [], 1
    while True:
        request = urllib.request.Request(
            f'https://api.github.com/repos/{repository}/commits/{sha}/check-runs'
            f'?per_page=100&page={page}',
            headers={'Authorization': f'Bearer {token}',
                     'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28'})
        with urllib.request.urlopen(request, timeout=30) as response:
            batch = json.load(response).get('check_runs', [])
        runs += batch
        if len(batch) < 100:
            return runs
        page += 1


def wait(load, timeout=3300, interval=30, clock=time.monotonic, sleeper=time.sleep,
         required=REQUIRED):
    deadline = clock() + timeout
    while True:
        state, problems = evaluate(load(), required)
        if state != 'pending':
            return state, problems
        if clock() >= deadline:
            return 'timeout', problems
        sleeper(interval)


if __name__ == '__main__':
    repository, sha, token = (os.environ[key] for key in ('GITHUB_REPOSITORY', 'COMMIT_SHA', 'GITHUB_TOKEN'))
    state, problems = wait(lambda: fetch(repository, sha, token))
    if state != 'passed':
        raise SystemExit('Required CI checks did not pass (' + state + '): ' + '; '.join(problems))
    print('All required CI checks passed for', sha)

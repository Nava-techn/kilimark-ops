# Session 5 - Scripting: Bash and Python for operations

**Session 5 / 24 · Automation 1** · One file for the whole session.

| Lab | What | Script | Status |
| --- | --- | --- | --- |
| S5.1 | Idempotent deploy, shellcheck clean | `scripts/session-05/s5.1-deploy-storefront.sh` | ✅ 18 Nov |
| S5.2 | Health check with an exit code, run by a systemd timer | `scripts/session-05/s5.2-healthcheck.{sh,service,timer}` | ✅ 18 Nov |
| S5.3 | Navatech product inventory in Python | `scripts/session-05/s5.3-inventory.py` | written + tested |
| S5.4 | Log analysis in Python, JSON export | `scripts/session-05/s5.4-log-report.py` | written + tested, to run on real logs |

Tested on 10 Nov in a sandbox (sample data, local web servers). The proofs below must come from **my** servers.

---

## S5.1 Idempotent deploy: `s5.1-deploy-storefront.sh` ✅

> **Goal:** Deploy the storefront with one command that can safely be run again.  
> **What changes:** Before, manual copy commands; after, versioned releases, an atomic switch, and an automatic rollback if the health check fails.

**Design:** each version gets its own folder, and the web root becomes a symlink.

```
/srv/navmarket-releases/1.0.0-7273466/    version + last Git commit that changed site/
/srv/navmarket -> navmarket-releases/...   Nginx serves the live release
```

**How it works:** pack `site/` → unpack next to the live site, rights included → switch the symlink atomically (`ln -sfn` + `mv -T`) → health check on the server itself (`curl --resolve name:443:127.0.0.1 https://name/health.json` must report the version) → if it fails, switch back and exit `1` → keep the 3 newest releases, never the live one, never a broken one.

| Option | vps01 | srv01 |
| --- | --- | --- |
| `-n` name for the health check | `kilimark.com` | `www.navmarket.lan` |
| `-g` team group | none: `root`, 755/644 | `webteamgrp`: 2775/664 (setgid, S1.2) |
| `-x` | test only: deploys a release without `health.json` to prove the rollback | |

**Done on 17 and 18 Nov:** shellcheck (0 warning) → first deploy on vps01 (the old folder kept as `legacy-...`) → second run "Nothing to do" → broken release on purpose → rollback → same script on srv01 with the team permissions.

**Proof** ([S5.1-proofs.txt](S5.1-proofs.txt)): shellcheck clean · both servers on `1.0.0-7273466` · srv01 `drwxrwsr-x root webteamgrp` · broken release: `404` → `FAILED` → `Rolled back` → exit code `1` · the script changed, `site/` did not → "Nothing to do" on both servers · `kilimark-storefront 1.0.0` from the Internet.

**Problems met (and fixed):**

- **`Permission denied`, exit 126:** the script lost its execute bit when the file was rewritten. `chmod +x`, then commit: Git keeps the bit. (127 would mean "command not found".)
- **Release folders dated from the past:** `tar` restores the files' own dates, so "keep the newest" sorted wrong. Fix: `touch` the release at deploy time.
- **A docs-only commit redeployed an identical site:** the name used the repo HEAD. Fix: `git log -1 --format=%h -- site`, the last commit that changed `site/`.
- **The cleanup kept a broken release and deleted a good one:** broken releases counted in "keep 3". Fix: delete `*-broken` first.
- **Never hide a sudo prompt:** the proofs use `tee` (screen + file), then remove the prompt lines.

## S5.2 Health check: `s5.2-healthcheck.sh` ✅

> **Goal:** Check the site's health with a script that returns an exit code.  
> **What changes:** Before, I checked by eye; after, cron or a CI pipeline knows automatically whether the site is OK, slow or down.

**Per URL:** HTTP `200` · `"status": "ok"` in `health.json` · response time under a limit (`-w`, 800 ms) · days left on the HTTPS certificate (`-d`, 14). The exit code is the **worst** result: `0` OK, `1` WARNING, `2` CRITICAL (the monitoring convention).

**Runs by itself:** a systemd **user** timer on my workstation (`s5.2-healthcheck.timer`, every 5 minutes, `Persistent=true`) starts `s5.2-healthcheck.service` (oneshot). Results go to `journalctl --user -u s5.2-healthcheck`; a non-zero exit code marks the service `failed`. Why a timer and not cron: logs and failures come for free, and missed runs are caught up.

**Done on 18 Nov:** both sites `OK` (kilimark.com 38 ms through the Internet, www.navmarket.lan 23 ms locally, certificates 88 and 389 days) → `/nope` gives `CRITICAL`, exit 2 → a 1 ms limit gives `WARNING`, exit 1 → timer installed → **real outage**: Nginx stopped on srv01.

**Proof** ([S5.2-proofs.txt](S5.2-proofs.txt)): exit codes `0 / 2 / 1` · timer every 5 minutes · outage: `CRITICAL ... curl error 7` (connection refused) + `no TLS certificate read`, service `failed` · Nginx restarted: 4 × `OK`, service no longer failed.

**Learned:** each check is independent (a missing page with a valid certificate is still `CRITICAL` overall); curl's error codes tell the layer (6 DNS, 7 refused, 28 timeout, 60 certificate); a oneshot service is `inactive` when it succeeded, `failed` when it did not.

## S5.3 Inventory in Python: `inventory.py`

> **Goal:** Manage the Navatech product inventory in Python, from a CSV file.  
> **What changes:** Before, raw data; after, a report per category, the products to reorder, and a JSON export.

Reads `scripts/session-05/s5.3-inventory.csv` (the 12 storefront products + stock), **checks every row** (bad numbers, duplicates: skipped and listed, exit `1`).

```bash
python3 scripts/session-05/s5.3-inventory.py report        # units and stock value per category
python3 scripts/session-05/s5.3-inventory.py low           # what to reorder
python3 scripts/session-05/s5.3-inventory.py json -o /tmp/inventory.json
```

Sandbox output: 12 products, 589 units, **23,146 €** of stock; to reorder: Glide mouse (**out of stock**), Volt 20K, Nava Buds.

Python used: `argparse` sub-commands, `csv.DictReader`, `dataclass`, type hints, `json`, exit codes.

## S5.4 Log analysis: `log_report.py`

> **Goal:** Analyse the Nginx logs in Python and export the results as JSON.  
> **What changes:** Before, a Bash report to read by eye; after, structured data that another tool can use.

The Python version of `nginx-report.sh` (S2.5): `.log` and `.gz`, oldest first, regex on the "combined" format.
JSON: period, requests, status codes, error rate, top IPs, top paths, requests per hour, **suspicious paths** (`wp-`, `.php`, `.env`, `.git`...). `--mask` hides the end of IPs before anything goes to Git.

```bash
scp scripts/session-05/s5.4-log-report.py srv01:/tmp/
ssh -t srv01 'sudo python3 /tmp/log_report.py /var/log/nginx/access.log* --mask -o /tmp/S5.4-report.json'
scp srv01:/tmp/S5.4-report.json docs/session-05/
```

**Bash or Python?** Bash to chain commands (S2.5). Python as soon as there is parsing, data structures or JSON: easier to read, test and extend.

---

## What I learned

- Idempotent + atomic + health check + rollback = a deploy I can run without fear.
- Exit codes are the language between scripts, cron and CI.
- shellcheck catches Bash bugs before they hit a server.
- Python for data: validate the input, keep going on bad rows, report them, export JSON.

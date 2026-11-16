# Session 4 - Network services: DNS, DHCP, HTTPS, firewall, reverse proxy

**Session 4 / 24 · Networking 2** · One file for the whole session. Proofs: `S4.x-proofs.txt` next to this file.

| Lab | What | Script | Status |
| --- | --- | --- | --- |
| S4.1 | Internal DNS for `navmarket.lan` (dnsmasq + split DNS) | manual + `scripts/session-04/s4.1-navmarket-split-dns.service` | ✅ 10 Nov |
| S4.2 | Automatic DHCP (DORA) | manual, see below | ✅ 10 Nov |
| S4.3 | HTTPS with my own certificate authority | `scripts/session-04/s4.3-https-lab-ca.sh` | ✅ 12 Nov |
| S4.4 | Firewall: only 22, 80, 443 open | `scripts/session-04/s4.4-navmarket-srv01.nft` | ✅ 13 Nov |
| S4.5 | Reverse proxy in front of 2 web servers | `scripts/session-04/s4.5-reverse-proxy.sh` | ✅ 14 Nov |
| S4.6 | Real domain + Let's Encrypt + fail2ban (vps01) | `scripts/session-04/s4.6-letsencrypt-vps.sh` | to run |
| S4.x | Incident: name no longer resolves, wrong gateway | `scripts/session-04/s4.x-incident.sh` | to run |

Every server-side script writes its own proofs and is run through `scripts/session-04/s4.4-run-on-srv01.sh`
(copy, `sudo` once, proofs copied back with the IP masked).

---

## S4.1 Internal DNS ✅

> **Goal:** Give names to the lab servers with an internal DNS.  
> **What changes:** Before, IP addresses everywhere; after, `www.navmarket.lan` works from my computer.

**Why:** people and scripts use **names**, not IPs. An IP can change; the name stays.

- `dnsmasq` on srv01 answers for `navmarket.lan` (`local=/navmarket.lan/`: never asked to the Internet), and forwards the rest.
- `host-record` = A + PTR (name ↔ IP), `cname` = alias (`www` → `navmarket-srv01`).
- **Split DNS** on my workstation: only `~navmarket.lan` goes to srv01 (`resolvectl dns/domain virbr0`), everything else uses the normal DNS.

**Proof** ([S4.1-proofs.txt](S4.1-proofs.txt)): `www` → CNAME → A, reverse lookup OK, `NXDOMAIN` for an unknown name, GitHub forwarded, `HTTP/1.1 200 OK` by name from the workstation.

## S4.2 Automatic DHCP ✅

> **Goal:** Hand out network settings automatically with DHCP.  
> **What changes:** Before, each machine needed a fixed IP typed by hand; after, a new machine gets its IP, gateway and DNS by itself, and its name in DNS.

**Why:** a new machine gets its IP, gateway, DNS and lease time by itself. No typing, no duplicate IPs.

**DORA:** **D**iscover (client broadcast) → **O**ffer (server proposes) → **R**equest (client accepts, broadcast) → **A**CK (confirmed).

- dnsmasq in the `router` namespace, pool `10.10.1.100-199` (the DHCP range of my S3.1 plan), lease 1 h.
- `dhcpcd` in `lan-a`. dnsmasq also put the client's name in DNS (`client-a.navmarket.lan`).

**Proof** ([S4.2-proofs.txt](S4.2-proofs.txt)): no IP before → DORA captured → `10.10.1.131/24` + `default via 10.10.1.1 proto dhcp` → lease line → name resolves → ping LAN B OK.

---

## S4.3 HTTPS with my own CA

> **Goal:** Serve the storefront over HTTPS with a certificate from my own certificate authority.  
> **What changes:** Before, clear-text HTTP; after, encrypted traffic and a trusted padlock on `www.navmarket.lan`.

**Why:** HTTP is clear text. TLS **encrypts** and **proves the server's identity** with a certificate signed by an authority the client trusts. `.lan` names can't get a public certificate, so companies run an **internal CA**.

| File | Where | Secret |
| --- | --- | --- |
| `ca.key` | only `~/projets/navmarket-ca` on my workstation | 🔴 never in Git, never on a server |
| `ca.crt` | trusted by my workstation | no |
| `navmarket.key` | srv01 `/etc/ssl/navmarket`, mode 600 | 🔴 |
| `navmarket.crt` | srv01 | no |

- `subjectAltName` = the names the certificate is valid for (browsers check this, not the CN).
- 397 days max: browsers reject longer server certificates.
- HTTP on the lab names → `301` to HTTPS; HTTP by IP still works.

```bash
scripts/session-04/s4.3-https-lab-ca.sh     # from the repo root, on the workstation
```

> **Incident during the lab (10 Nov):** the first run created the CA files **inside the repo**. Nothing was committed. The script now moves them to `~/projets/navmarket-ca`, and `.gitignore` blocks `*.key`, `*.csr`, `ca.crt` for good.

**Done step by step on 12 Nov:** look at srv01 first (one site, `root /srv/navmarket`, port 80 only) → certificate installed (`.crt` 644, `.key` 600, root only) → `navmarket-tls` site (port 80 on the `.lan` names redirects, port 443 serves the storefront), `nginx -t` then `reload` → CA trusted on the workstation (`update-ca-certificates`).

**Proof** ([S4.3-proofs.txt](S4.3-proofs.txt)): issuer `NavMarket Lab Root CA`, `OK` · another trust store: exit `60` · with my CA: `200 OK` without `-k` · `TLSv1.3`, `Verify return code: 0 (ok)` · HTTP on the name → `301` to HTTPS · HTTP by IP still `200`.

**Problems met:**

- **Name no longer resolved** (`curl: (6)`, `ERR_NAME_NOT_RESOLVED`). Diagnosis: srv01's DNS answered (`dig @srv01`), but the workstation had **forgotten the split DNS** after a reboot (`resolvectl` settings live in memory). Fix: set it again. Prevention: `navmarket-split-dns.service`, a systemd unit tied to `virbr0` that re-applies it every time the interface appears.
- **`curl: (7)` on port 443** = connection refused in 1 ms: nothing listening, the HTTPS site was not enabled yet. A firewall would have given a timeout instead.
- **The "untrusted" test passed by mistake:** `--cacert` only replaces the CA **file**; curl also reads the CA **folder** `/etc/ssl/certs/`, where my CA had just been added. Fix: `--capath` to an empty folder too.
- **`grep -r` found nothing in `sites-enabled/`:** it skips symlinks. `grep -R` follows them.

## S4.4 Firewall: only 22, 80, 443 ✅

> **Goal:** Close every door of srv01 except SSH, HTTP and HTTPS (plus DNS for my lab network).  
> **What changes:** Before, any program listening on srv01 was reachable; after, a forgotten service stays blocked by default.

**Why:** every open port is a door. **Default deny**: drop everything, then open only what is needed.

**Done step by step on 13 Nov:**

1. **Look first** (`ss -tulpn`): 22 sshd, 80/443 nginx, 53 dnsmasq, local-only services (resolved, chronyd), and **68/udp, the DHCP client of srv01**: srv01 rents its IP from libvirt, so the DHCP answers must get through or srv01 loses its IP.
2. **Rules** in [`s4.4-navmarket-srv01.nft`](../../scripts/session-04/s4.4-navmarket-srv01.nft) (nftables): `policy drop`, `established,related` first, `lo` and ICMP, TCP 22/80/443, DNS 53 **only from my lab network**, DHCP answers, drops logged. Checked with `nft -c` before applying.
3. **Applied with a safety net:** a `systemd-run` timer deletes the firewall after 120 s; a **new** SSH connection proved port 22 still works, then the timer was cancelled.
4. **Permanent:** `/etc/nftables.d/navmarket.nft`, included from `/etc/nftables.conf`, `nftables.service` enabled.

**Proof** ([S4.4-proofs.txt](S4.4-proofs.txt)): from my computer 22, 80, 443 `OPEN`, test port 8081 `BLOCKED` · the same port answers `HTTP 200` inside srv01 · the blocked attempts appear as `nft-drop:` in `journalctl -k` · boot config `syntax OK`, `enabled`.

## S4.5 Reverse proxy in front of 2 web servers ✅

> **Goal:** Put Nginx in front of 2 web servers that share the visitors.  
> **What changes:** Before, one server was a single point of failure; after, one server can go down without visitors noticing.

```
                             ┌──▶ web1  127.0.0.1:8081
browser ──HTTPS──▶ Nginx ────┤        (round robin)
          /lb/    (proxy)    └──▶ web2  127.0.0.1:8082
```

**Done step by step on 14 Nov:**

1. **Two backends:** `navmarket-web@1` and `@2`, one systemd **template** (`%i` = 1 or 2), Python's HTTP server on `127.0.0.1` only, `DynamicUser`, `Restart=always`. Each serves a `health.json` saying who it is.
2. **The proxy:** `upstream navmarket_backends` in `conf.d/` (round robin, `max_fails=1 fail_timeout=10s`), and `location /lb/` in its own file, pulled into the HTTPS site with one `include`. `X-Forwarded-For` / `X-Real-IP` give the backends the real client IP.
3. **Failover test:** web2 stopped on purpose, then started again.

**Proof** ([S4.5-proofs.txt](S4.5-proofs.txt)): both up → web1 and web2 share the requests · web2 stopped → 6 × `200` from web1 · Nginx logged `connect() failed (111: Connection refused)` once, retried on web1, then set web2 aside for 10 s · web2 back → traffic shared again · backends still on `127.0.0.1` only.

**Problems met:**

- **`active` but nothing listening:** the check ran milliseconds after the start. `active` means "process started", not "ready to answer": a real check asks the service itself (a **readiness probe** in Kubernetes words).
- **First request gave `404`, no `X-Backend` header:** `systemctl reload` only sends a signal; the request was still served by an old worker with the old config. `nginx -T` showed the new route was loaded; a second try worked.
- **Order web1, web1, web2:** each Nginx worker keeps its own round-robin counter.
- **Script bug found:** `if nginx -t | tail -1` tests `tail`, not `nginx`. In a pipe, `$?` is the last command's result.

## S4.6 Real domain + Let's Encrypt + fail2ban (vps01)

> **Goal:** Give the public server a real domain name with a Let's Encrypt certificate, and ban SSH attackers with fail2ban.  
> **What changes:** Before, the public site was HTTP by IP; after, HTTPS trusted by every browser, renewed automatically, and brute-force attackers banned.

**Why:** a public name and a certificate trusted by every browser, renewed automatically; and SSH brute force blocked (S2.6 showed the attacks).

**Before (by hand, 10 min):**

1. A free domain: [duckdns.org](https://www.duckdns.org) (sign in, create `something.duckdns.org`, set it to vps01's public IP).
2. Oracle console: security list → add ingress **TCP 443** from `0.0.0.0/0` (like port 80 in S1.5).
3. `~/.ssh/config` on the workstation:

```
Host vps01
    HostName <PUBLIC_IP>
    User ubuntu
    IdentityFile ~/.ssh/navmarket_vps
```

```bash
scripts/session-04/s4.4-run-on-srv01.sh scripts/session-04/s4.6-letsencrypt-vps.sh docs/session-04/S4.6-proofs.txt \
    vps01 DOMAIN=something.duckdns.org EMAIL=my@email
```

- Let's Encrypt checks I control the domain (HTTP-01 challenge on port 80), then signs a **90-day** certificate; `certbot.timer` renews it.
- fail2ban: 5 failed SSH logins in 10 min → banned 1 h.

**Expected:** domain = public IP · `HTTP/1.1 200` in HTTPS, HTTP → `301` · issuer Let's Encrypt, `Verify return code: 0` · renew dry run succeeds · `sshd` jail active.

## S4.x Incident: "the name no longer resolves, wrong gateway"

> **Goal:** Troubleshoot "the name no longer resolves, wrong gateway" layer by layer.  
> **What changes:** Before, I would guess; after, I find the cause in minutes with a method: IP, route, gateway, DNS.

**Story:** after a bad change, a client in LAN A can't reach the web server, by IP **or** by name.

**Method, bottom to top:**

1. My IP and routes: `ip -br addr`, `ip route`.
2. My gateway: `ping` it, `ip neigh` (ARP `INCOMPLETE`/`FAILED` = nobody there).
3. The DNS server I use: `/etc/resolv.conf`.
4. Ask the right DNS server directly: `dig @10.10.1.1 name`.

**Two causes:** default route via `10.10.1.254` (does not exist), and `resolv.conf` → `10.10.1.53` (no DNS there). **Fix:** `ip route replace default via 10.10.1.1` + the right nameserver.

```bash
scp scripts/session-03/s3.2-lab-netns.sh srv01:/tmp/
scripts/session-04/s4.4-run-on-srv01.sh scripts/session-04/s4.x-incident.sh docs/session-04/S4.x-proofs.txt
```

**Expected:** OK → FAILED / FAILED → diagnosis shows both causes → OK / OK. The lab cleans itself.

---

## What I learned

- DNS turns names into IPs; split DNS sends only my internal domain to my server.
- DHCP = DORA; a lease is temporary; DHCP can also feed DNS.
- TLS = encryption + identity. Trust comes from the CA; a private key never leaves its machine and never goes to Git.
- Firewall: default deny, open the minimum, always keep a way back (rollback timer).
- A reverse proxy is one entry point in front of several servers: load sharing and failover.
- Let's Encrypt: free, trusted, 90 days, automatic renewal. fail2ban turns log lines into bans.
- Troubleshoot network problems layer by layer: IP → route → gateway (ARP) → DNS.

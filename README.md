# Kilimark Ops

> I build and run, end to end, the platform behind an online shop: from the very first Linux server all the way to Kubernetes on AWS.
> Every step is a real lab, documented, with proof.

**Current progress: session 4 / 24** · [See my live progress](https://nava-techn.github.io/navmarket-roadmap/)
**LinkedIn:** [Write to me on LinkedIn, I'll answer](https://www.linkedin.com/in/valdes-nague/)

---

## The project

**Kilimark** (formerly NavMarket) is the online shop whose platform I build and run. I am its operations (Ops) engineer: servers, network, security, deployment and monitoring. Its demo storefront is live at **https://kilimark.com**.

The learning path follows the order in which a real platform grows:

| Phase | Sessions | Topic |
| --- | --- | --- |
| Foundations | 1 to 8 | Linux, networking, Bash and Python, virtualization, Git |
| Application | 9 to 10 | NestJS API + Next.js front end + PostgreSQL |
| Containers and CI/CD | 11 to 12 | Docker, GitHub Actions |
| AWS Cloud | 13 to 16 | IAM, VPC, EC2, RDS, ECS Fargate |
| Infrastructure as Code | 17 to 18 | Terraform, Ansible |
| Kubernetes | 19 to 21 | kind, Helm, Argo CD, EKS, CKA |
| Observability and final project | 22 to 24 | Prometheus, Grafana, Loki, postmortem |

## Completed labs

Each lab has its own write-up in `docs/`: goal, approach, proof, problem encountered, what I learned.

| Session | Lab | Write-up | Status |
| --- | --- | --- | --- |
| 1 | Linux workstation (Ubuntu 26.04 LTS in dual boot) | - | ✅ |
| 1 | S1.1 First server `navmarket-srv01`: Ubuntu Server 26.04.1 LTS on KVM/libvirt, administered over SSH, fully updated, snapshot | [S1.1](docs/session-01/S1.1-first-server.md) | ✅ |
| 1 | S1.2 Accounts alice, bob, chloe: shared web directory `/srv/navmarket` (group, setgid, umask) | [S1.2](docs/session-01/S1.2-accounts-permissions.md) | ✅ |
| 1 | S1.3 NavMarket storefront served by Nginx from `/srv/navmarket` | [S1.3](docs/session-01/S1.3-nginx-storefront.md) | ✅ |
| 1 | S1.4 OverTheWire Bandit levels 0 → 10: file names, find, grep, pipes, base64 | [S1.4](docs/session-01/S1.4-bandit-0-10.md) | ✅ |
| 1 | S1.5 Storefront public over HTTPS with a Cloudflare Quick Tunnel (plan B, Oracle out of capacity) | [S1.5](docs/session-01/S1.5-cloudflare-tunnel.md) | ✅ |
| 2 | Linux administration: SSH with keys only, self-healing systemd service, nightly backups, full-disk diagnosis, analysis of real attacks in the logs, Nginx incident | [Session 2](docs/session-02/) | ✅ |
| 3 | Networking: addressing plan, Linux router, annotated packet capture, NAT to the Internet | [Session 3](docs/session-03/) | ✅ |
| 4 | Network services: internal DNS and DHCP, HTTPS with my own certificate authority, nftables firewall, reverse proxy with failover, **kilimark.com** live with Let's Encrypt and fail2ban, network incident solved layer by layer | [Session 4](docs/session-04/S4-network-services.md) | ✅ |

*This table is updated every time a lab is completed.*

## Repository layout

```
kilimark-ops/
├── README.md      ← this page
├── docs/          ← one write-up per lab, organized by session
├── scripts/       ← Bash and Python scripts, one folder per session (session-01...)
├── nginx/         ← web server configurations
└── site/          ← the Kilimark storefront
```

*This structure grows session by session.*

## About the names

The project was called **NavMarket** until 16 November 2026, then renamed **Kilimark**. Past write-ups and proofs keep the old name: they record what happened at the time.
Internal technical names (`navmarket-srv01`, `navmarket-vps01`, `/srv/navmarket`, `navmarket.lan`, systemd units) also keep `navmarket` for now: renaming running infrastructure is a planned change of its own, to be automated later.

## Method

- **I type and understand every command**: nothing is copied without being explained in the lab write-up.
- **One proof per lab**: a screenshot, a command output or a link to the live service.
- **Failures caused on purpose, then fixed**: some labs deliberately break something so I learn to troubleshoot.
- **No secrets in this repository**: no passwords, no keys, no server addresses (see `.gitignore`).

## Contact

- Progress: [See my progress](https://nava-techn.github.io/navmarket-roadmap/)
- GitHub: [My GitHub](https://github.com/nava-techn)
- LinkedIn: [Write to me on LinkedIn, I'll answer](https://www.linkedin.com/in/valdes-nague/)

# Homelab hosts (odin, thor, loki)

Ansible that reproduces the three Nomad/Consul hosts **as they were on
2026-11-09**, so a wiped box can be rebuilt from it. It was written from
read-only surveys of the live hosts. The templates render byte-identical to
the live files (checked with `cmp`). A `--check --diff` run against all three
hosts reported **0 changed**.

| host | IP            | extra                                           |
|------|---------------|-------------------------------------------------|
| odin | 192.168.1.100 | OpenVPN udp/1194, check-mk agent, user crontab  |
| thor | 192.168.1.101 | OpenVPN udp/1195, zfsutils (unused)             |
| loki | 192.168.1.102 | -                                               |

All three are Dell OptiPlex 5060s (6 cores, 32 GB, 512 GB NVMe) running Debian 13.5
(trixie). Each one is a Nomad server+client and a Consul server (3-node Raft each).

## What it reproduces

| role       | what                                                                                       |
|------------|--------------------------------------------------------------------------------------------|
| `packages` | Debian `sources.list` (+ trixie-backports), Docker + HashiCorp repos/keys, pinned nomad 2.0.3-1, consul 2.0.0-1, docker-ce 29.5.3, containerd.io 2.2.4, buildx, compose, nomad-driver-virt; the manually-installed package set (common + per host) |
| `base`     | hostname, `/etc/hosts`, Europe/London, en_GB.UTF-8 (`/etc/locale.conf` + symlink), gb keyboard, timesyncd |
| `network`  | `/etc/network/interfaces` (eno1 **DHCP** via ifupdown + dhcpcd)                            |
| `users`    | ayden groups (incl. docker), the 2 authorized public keys, `%sudo NOPASSWD: ALL`, odin's crontab line |
| `storage`  | NFS `/storage` ← `192.168.1.103:/mnt/superfast/sonic` (nfs4 4.2, hard, actimeo=1), checks the top-level layout |
| `docker`   | services enabled; **no** `daemon.json` (defaults: overlay2, json-file, systemd cgroups)    |
| `cni`      | CNI reference plugins v1.6.2 in `/opt/cni/bin` (checksum-verified upstream tarball)        |
| `virt`     | libvirtd/virtlockd/virtlogd/dnsmasq enabled, `/dev/kvm` check (Nomad qemu + virt drivers)  |
| `openvpn`  | odin/thor: `server.conf`, `openvpn-iptables.service`, ip_forward sysctl; PKI is opt-in from vault |
| `consul`   | `/etc/consul.d/consul.hcl` (stock HashiCorp example + cluster settings), dirs, service     |
| `nomad`    | `/etc/nomad.d/nomad.hcl` (per-host advertise), `bridge`/`br_netfilter` modules, dirs/perms, nomad-driver-virt in `/opt/nomad/plugins`, service |

The per-host values are `host_ip`, `nomad_hcl_layout`, `packages_extra`, the
OpenVPN port, and odin's cron line, all in `host_vars/`. Consul `retry_join` is
computed as the other two hosts' IPs, sorted, which matches every host today.

## Usage

```sh
cd ansible
ansible-galaxy collection install -r requirements.yml

# Read-only drift check (zero "changed" == hosts match the repo)
ansible-playbook site.yml --check --diff
# or, forced check mode even without --check:
ansible-playbook drift-check.yml --diff

# Apply (one host at a time)
ansible-playbook site.yml --diff
ansible-playbook site.yml --diff --tags nomad -l thor
```

Become uses passwordless sudo (the `%sudo NOPASSWD` rule the repo itself
manages). There is never a password prompt.

### Rolling restarts and quorum

`site.yml` runs with `serial: 1`, `any_errors_fatal` and `max_fail_percentage: 0`.
Handlers flush at the end of each host. A config change restarts that host's
agent, and the next host does not start until:

* Consul: `/v1/agent/members` shows this node with `Status == 1` (alive), and
  `/v1/status/leader` is non-empty;
* Nomad: `/v1/nodes?filter=Name == "<host>"` shows `Status == "ready"`, and
  `/v1/status/leader` is non-empty.

So 2 of 3 servers stay up the whole time. A Nomad agent restart leaves
allocations running (`KillMode=process`), so no drain is needed. A Docker
restart **does** kill containers (live-restore is off), so drain the node
first (`nomad node drain -enable -self`).

### Secrets

Nomad and Consul config hold no secrets today: ACLs, TLS and Consul gossip
encryption are all off (`encrypt` is only the commented stock example). The
only secrets on the hosts are the OpenVPN server PKI and the public VPN
endpoint. To manage them:

```sh
cp group_vars/all/vault.yml.example group_vars/all/vault.yml   # gitignored
$EDITOR group_vars/all/vault.yml && ansible-vault encrypt group_vars/all/vault.yml
ansible-playbook site.yml -e openvpn_manage_pki=true --ask-vault-pass
```

## Bootstrapping a new / wiped box

1. Install Debian 13 netinst (amd64, UEFI, ext4 `/`, swap, SSH server, standard
   utilities). Create user `ayden` with sudo, and set locale en_GB.UTF-8 and
   keyboard gb.
2. On the router, give its NIC the same DHCP reservation (192.168.1.10x). Nothing
   on the host pins the IP.
3. `ssh-copy-id ayden@<ip>`, then run `sudo visudo` once on the box if
   passwordless sudo is not there yet (or run the first time with `-K`).
4. `ansible-playbook site.yml -l <host> --diff`.
5. Raft data in `/opt/consul` and `/opt/nomad/server` is **not** in this repo.
   With the other two servers healthy, a fresh agent joins and replicates
   automatically. Before rejoining with the same name, remove the dead peer:
   `consul operator raft remove-peer`, `nomad server force-leave`.
6. NVIDIA: `nvidia-driver` builds through DKMS and needs the matching
   `linux-headers-$(uname -r)`. Reboot once afterwards.

## Not covered (deliberately or not reproducible)

* **The keepalived VIP 192.168.1.240** is a Nomad job, not host config.
* **Nomad jobs/allocs, Docker images/volumes, Raft state.** These live in
  Nomad/Consul or on NFS.
* **Root/EFI/swap fstab lines** (installer, per-disk UUIDs) and the
  commented-out legacy NFS lines.
* **check-mk-agent 2.4.0p13** on odin. It comes from a .deb served by the
  Checkmk site, not from any apt repo.
* **nomad-driver-virt 0.0.1~beta.1-1** is no longer in the HashiCorp apt index.
  The pinned install only works while a copy is in
  `/var/cache/apt/archives` or another repo provides it.
* **OpenVPN PKI and client profiles** (`~ayden/openvpn/*.ovpn`, easy-rsa dir).
  Only written with vault data.
* **The libvirt domains/networks** created by nomad-driver-virt (runtime state).
* Leftovers that are kept but not managed: `/opt/vault` (a vault user with no
  package or unit; odin also has a dangling `vault.service` symlink), the
  NAS-side ownership of `/storage/*`, home-directory scripts
  (`restart_all_nomad_jobs.sh`, `force_restart.sh`, `~/docker-compose`, `~/traefik`).
* Stock, unmodified files (shown by `dpkg -V`): sshd_config, timesyncd.conf,
  containerd `config.toml`, dhcpcd.conf, dnsmasq.conf, nfs.conf. The packages
  provide them.

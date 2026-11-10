# Cluster snapshot backups

Job: `cluster-snapshot-backup` (daily 03:30 Europe/Dublin). It saves a Consul snapshot and a Nomad snapshot, encrypts each with the public key `8C2ACE04A26EC08625EB0FF371DD90AE4AE92742` (`keys/homelab-backup.asc`), and writes only `.gpg` files to NFS:

- `/storage/nomad/cluster-snapshot-backup/consul/consul-YYYYmmdd-HHMMSS.snap.gpg`
- `/storage/nomad/cluster-snapshot-backup/nomad/nomad-YYYYmmdd-HHMMSS.snap.gpg`

Files older than `backup/retention/days` (Consul KV) are deleted. The private key is never on the cluster.

## Decrypt (on the Mac, where the private key lives)

```sh
gpg --decrypt consul-20260101-033000.snap.gpg > consul.snap
gpg --decrypt nomad-20260101-033000.snap.gpg  > nomad.snap
```

Delete the plaintext files when finished.

## Restore

Consul (run against a healthy server; this replaces all Consul state):

```sh
export CONSUL_HTTP_ADDR=http://192.168.1.100:8500
consul snapshot inspect consul.snap
consul snapshot restore consul.snap
```

Nomad (replaces all Nomad state: jobs, allocations, variables):

```sh
export NOMAD_ADDR=http://192.168.1.100:4646
nomad operator snapshot inspect nomad.snap
nomad operator snapshot restore nomad.snap
```

Full cluster loss: bootstrap new servers, restore Consul first, then Nomad.

## Test procedure

1. Force a run: `nomad job periodic force cluster-snapshot-backup`, then check the alloc logs and the Discord message.
2. Copy the newest `.gpg` files from `/storage/nomad/cluster-snapshot-backup/{consul,nomad}/` to the Mac.
3. Confirm the files are encrypted: `file consul-*.snap.gpg` should say PGP, not data from Consul.
4. Decrypt as above, then run `consul snapshot inspect consul.snap` and `nomad operator snapshot inspect nomad.snap`. Both should print index/term metadata.
5. Confirm no plaintext `.snap` exists on NFS: `find /storage/nomad/cluster-snapshot-backup -name '*.snap'` returns nothing.
6. Optional restore drill: start a throwaway single-node `consul agent -dev` and run `consul snapshot restore consul.snap` against it (likewise `nomad agent -dev`). Never test-restore on the live cluster.

## Off-site copy

Each encrypted file is also uploaded to `gdrive:backups/cluster-snapshots` with the host's rclone config, the same as the other backup jobs. The same `backup/retention/days` pruning applies there.

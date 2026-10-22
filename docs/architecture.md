# Architecture — terraform-ansible-implementation

## The pattern

```
   terraform/ (provisions)              ansible/ (configures)
  ┌───────────────────────────┐     ┌─────────────────────────────┐
  │  main.tf                  │     │  inventory.ini (RFC1918)    │
  │  ┌─────────┐  ┌────────┐  │     │  playbooks/                 │
  │  │  VNet   │──│ subnet │  │     │   ├─ baseline.yml (harden)  │
  │  │  NSG    │  │  VM    │  │     │   ├─ deploy-app.yml (site)  │
  │  └─────────┘  └────────┘  │     │   └─ patch.yml (updates)    │
  │  versions.tf (pinned      │     └─────────────────────────────┘
  │  provider 4.47.0)         │
  └───────────────────────────┘
        outputs.tf → feeds ansible inventory (terraform output -json)
```

Terraform draws the map and builds the roads; Ansible furnishes the
houses. That division is deliberate: Terraform is *declarative desired
state for things that exist* (resource groups, networks, VMs), Ansible is
*procedural-ish convergence for things inside them* (users, SSH config,
packages, services). Each tool does the job it was built for.

## Design decisions

**Pinned providers (`version = "4.47.0"`, not `~> 4.0`).**
The azurerm provider is large and moves fast — resource schemas and default
behaviors change between minor versions. An unpinned constraint means
`terraform init` on a fresh machine can silently pull a newer provider than
the one you validated against, and a plan that was green yesterday goes red
today. Pinning the exact version plus the generated lock file
(`.terraform.lock.hcl`, gitignored in this implementation but committed in real
projects) makes `init` reproducible anywhere. The cost is that upgrades
become an explicit, reviewable act (`terraform init -upgrade`) — which is
exactly what you want for infrastructure.

**Local state for the implementation, remote-state template for anything real.**
State is the database of what Terraform believes exists. Local state
(`terraform.tfstate` on disk) is fine for one person experimenting: no
storage account to provision, nothing to lock. It breaks the moment a
second operator, a CI runner, or a lost laptop enters the picture — then
you need the azurerm backend (commented template in `versions.tf`) with
blob leasing so applies serialize and a corrupted state file becomes
someone else's problem. The rule of thumb: state must live somewhere the
whole team can reach and nobody can write to by accident.

**One VM, one subnet, explicit NSG rules — kept small on purpose.**
The demo pattern is a single Linux VM because the implementation's subject is the
*workflow* (plan → apply → configure → patch), not scale. The NSG spells
out an explicit `deny-all-inbound` at priority 4096 even though Azure's
default is already deny — documented intent beats implicit behavior when
someone audits the rules at 2am.

**SSH key injection via `file(pathexpand(...))`.**
The VM's public key is read from the operator's disk at plan time, never
checked into the repo. `pathexpand()` handles `~`; `file()` failing on a
missing `.pub` aborts the plan *before* anything is created — better to
fail loudly than to deploy a VM you can't log into. No passwords anywhere:
`disable_password_authentication = true` and Ansible hardens SSH to
key-only.

**Playbooks, not roles — right call at this size.**
Ansible roles are the answer when you have reusable units (an `nginx` role
used across five projects) or a team splitting work. This implementation has three
focused playbooks with shared variables in `group_vars/all.yml`; wrapping
each in role scaffolding (`tasks/`, `handlers/`, `defaults/`,
`meta/`) would add directory noise without reuse. If a second project
needs the same baseline, *that's* when you extract a role.

**Ubuntu 24.04 LTS as the base image.**
Current LTS, five years of support, and the image reference is pinned to
the Canonical publisher with a `server` SKU rather than a specific image
version — for this implementation, "latest LTS at apply time" is fine; for production
you'd pin the image version and control upgrades explicitly.

**SSH key via managed file, not the authorized_key module.**
`ansible.posix.authorized_key` is the textbook tool, but it ships in the
ansible.posix Galaxy collection — not in ansible-core. The implementation is
deliberately 100% ansible-core (`pip install ansible-core` and nothing
else), so baseline.yml manages `~/.ssh/authorized_keys` as a file with
explicit owner/permissions instead. Idempotent, no downloads, works
anywhere; the playbook comments document the upgrade path.

**UFW tasks use `command` with state checks, not a module.**
ansible-core ships no `ufw` module (it lives in `community.general`).
Rather than add a collection dependency to the implementation, the tasks read
`ufw status verbose` once and only run the mutating commands when the
state demands it. Same idempotency, zero dependencies — at the cost of
parsing CLI output, which is documented inline as the fragile part.

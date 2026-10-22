# Terraform + Ansible Implementation — Infrastructure as Code for Systems Roles

A demo-grade Infrastructure as Code stack: **Terraform** provisions the
network and the VM on Azure, **Ansible** configures what's inside it.
Provisioning and configuration are deliberately two tools, not one —
see `docs/architecture.md` for why.

**What this demonstrates:** a complete small Terraform config against
the azurerm provider (pinned version, typed variables, explicit NSG
rules, key-only SSH with the public key read from disk at plan time),
three idempotent Ansible playbooks (baseline hardening, app deploy,
patching with reboot-if-needed), a state/drift/secrets runbook, and the
discipline of never letting secrets or real IDs near the repo.

```
   terraform/ (provisions)              ansible/ (configures)
  ┌───────────────────────────┐     ┌─────────────────────────────┐
  │  RG ──▶ VNet ──▶ subnet   │     │  inventory.ini (RFC1918)    │
  │  NSG (ssh / http-vnet /   │     │  playbooks/                 │
  │       deny-all)           │     │   ├─ baseline.yml (harden)  │
  │  NIC + pip ──▶ 1 Linux VM │     │   ├─ deploy-app.yml (site)  │
  │  pinned azurerm 4.47.0    │     │   └─ patch.yml (updates)    │
  └───────────────────────────┘     └─────────────────────────────┘
        outputs.tf ──feeds──▶ terraform output -json ▶ ansible inventory
```

## Repo layout

| Path | Purpose |
|---|---|
| `terraform/main.tf` | RG, VNet + subnet, NSG with explicit rules, NIC, public IP, one Ubuntu VM |
| `terraform/variables.tf` | Typed variables with defaults — all placeholder/fictional values |
| `terraform/outputs.tf` | RG name, VNet/subnet/NSG IDs, VM name + public IP (glue for Ansible) |
| `terraform/versions.tf` | Terraform `>= 1.9.0`, azurerm pinned to `4.47.0`, commented remote-state backend template |
| `terraform/terraform.tfvars.example` | Example values — copy to `terraform.tfvars` (gitignored), never commit real ones |
| `ansible/inventory/inventory.ini.example` | Fictional RFC 1918 hosts — copy to `inventory.ini` (gitignored) |
| `ansible/inventory/group_vars/all.yml.example` | Fictional variables + SSH placeholder key — copy to `all.yml` (gitignored) |
| `ansible/playbooks/baseline.yml` | Admin user, SSH hardening, base packages, UFW deny-by-default |
| `ansible/playbooks/deploy-app.yml` | nginx + static demo site, restart-via-handler pattern |
| `ansible/playbooks/patch.yml` | apt upgrades, reboots only if the OS flags it AND `allow_reboot` is true |
| `docs/architecture.md` | Design decisions: pinned providers, state strategy, roles vs playbooks |
| `docs/iac-workflow.md` | Runbook: init → plan → apply → state, drift detection, secrets guidance |

## Quick start

```bash
# --- Terraform (needs the terraform CLI; no Azure account needed to validate)
cd terraform
terraform init -backend=false   # downloads the pinned provider
terraform fmt -check -recursive
terraform validate

# --- Ansible (pip install ansible-core — no collections needed)
cd ../ansible
cp inventory/inventory.ini.example inventory/inventory.ini
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
# edit both: real hosts, your real SSH public key
ansible-playbook --syntax-check -i inventory/inventory.ini playbooks/baseline.yml
ansible-playbook -i inventory/inventory.ini playbooks/baseline.yml
```

Against a real Azure subscription the order is: `terraform init` →
`plan -out=tfplan` → `apply tfplan` → feed `terraform output -json` into
Ansible → run the playbooks. Full sequence in `docs/iac-workflow.md`.

## Security notes

- **No real credentials or IDs anywhere in this repo.** The subscription
  ID is the all-zero placeholder, the SSH key in `group_vars` is a
  labeled fake, every host is RFC 1918 fiction. A secret scan is part of
  validation below.
- **Key-only SSH, everywhere.** The VM disables password auth; Ansible's
  baseline playbook turns off root login and password authentication in
  `sshd_config`. The public key is injected from the operator's disk at
  plan time (`file(pathexpand(...))`), so a missing `.pub` fails the plan
  before a VM you can't reach gets created.
- **Explicit default-deny NSG.** Inbound SSH from the home network range only, HTTP
  inside the VNet only, then a documented `deny-all-inbound` rule —
  intent spelled out, not left to Azure's implicit default.
- **State is sensitive.** `.gitignore` blocks `*.tfstate`, `.terraform/`,
  real `.tfvars`, vault password files, and copied-in inventories/vars.
  State can contain secrets in plaintext — the runbook covers locking it
  down.

## Validation (actually run locally)

Terraform — standalone binary 1.16.6 from releases.hashicorp.com,
real `init` (pinned azurerm 4.47.0 downloaded from the registry) and
`validate`. `main.tf` was auto-formatted with `terraform fmt` during this
run; validate re-ran green after.

```
$ terraform init -backend=false
- Finding hashicorp/azurerm versions matching "4.47.0"...
- Installing hashicorp/azurerm v4.47.0...
Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.

$ terraform fmt -check -recursive
(main.tf reformatted once — validate re-ran green after)
```

Ansible — `ansible-core 2.21.5` installed via pip, every playbook syntax
checked against the example inventory:

```
$ ansible-playbook --syntax-check -i inventory/inventory.ini.example playbooks/baseline.yml
playbook: playbooks/baseline.yml          (exit 0)

$ ansible-playbook --syntax-check -i inventory/inventory.ini.example playbooks/deploy-app.yml
playbook: playbooks/deploy-app.yml        (exit 0)

$ ansible-playbook --syntax-check -i inventory/inventory.ini.example playbooks/patch.yml
playbook: playbooks/patch.yml             (exit 0)
```

Parsing — all 4 YAML files (3 playbooks + example group_vars) parse with
Python `yaml.safe_load`; the example inventory parses with
`ansible-inventory --list` (3 hosts: web01, web02, db01, correct groups
and hostvars). HCL was reviewed plus the real `terraform validate` above
(no eyeball-only check needed).

Secret/ID scan — clean. The only GUID-shaped string in the repo is the
documented all-zero placeholder in `variables.tf` /
`terraform.tfvars.example`; the only key-shaped string is the labeled
`...PLACEHOLDER` fake in `all.yml.example`; no private key material, no
hardcoded passwords anywhere.

Honest notes:
- The first `terraform init` failed with "no space left on device" — the
  local `/tmp` is a 512M tmpfs and the azurerm provider binary is
  huge. Reran with `TMPDIR` pointed at a roomier home-directory path and
  init succeeded. That's an environment quirk, not a config problem.
- `ansible-galaxy collection install` failed locally (repeated
  `IncompleteRead` from galaxy.ansible.com), so this implementation deliberately uses
  zero collections — 100% ansible-core modules plus `command:` tasks with
  state checks for UFW. The baseline playbook documents the
  `ansible.posix.authorized_key` upgrade path in a comment.
- **Not validated (needs a real cloud):** `terraform plan`/`apply`
  against an actual Azure subscription, and running the playbooks against
  real hosts — those need an account, money, and SSH reachability, none
  of which are available here. Nothing in this repo pretends otherwise.

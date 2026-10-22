# IaC workflow runbook — terraform-ansible-implementation

## 1. Init

```bash
cd terraform
terraform init          # downloads the pinned azurerm provider
```

`init` reads `versions.tf`, pulls exactly `hashicorp/azurerm` 4.47.0, and
writes `.terraform.lock.hcl` (checksums — your reproducibility receipt).
Use `-backend=false` when you only want syntax validation without touching
state. Use `-upgrade` when you deliberately want a newer provider, then
review the plan *extra* carefully.

## 2. Plan

```bash
terraform fmt -check -recursive   # style gate before review
terraform validate                # schema + syntax check (needs init first)
terraform plan -out=tfplan        # dry run: what WOULD change
```

Read the plan like a change request: every `+`/`-`/`~` is a diff against
live state. Nothing is touched yet. Save the plan file and apply *that
exact file* — it prevents the classic "I planned on Monday, the world
changed by Wednesday" surprise.

## 3. Apply

```bash
terraform apply tfplan
```

Terraform talks to Azure, creates/updates resources in dependency order
(RG → VNet → subnet → NSG → NIC → VM), and writes the new reality to
`terraform.tfstate`. Capture outputs for the next stage:

```bash
terraform output -json > ../ansible/terraform-outputs.json
```

## 4. Configure with Ansible

```bash
cd ../ansible
cp inventory/inventory.ini.example inventory/inventory.ini
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
# edit both: real hosts, your real (never committed) SSH public key

ansible-playbook -i inventory/inventory.ini playbooks/baseline.yml   # harden
ansible-playbook -i inventory/inventory.ini playbooks/deploy-app.yml # deploy
ansible-playbook -i inventory/inventory.ini playbooks/patch.yml     # patch
```

The bridge between the two tools is `terraform output`: the VM's public IP
can feed a dynamic inventory or be pasted into `inventory.ini` — no
hardcoded cloud IPs in committed files.

## 5. State management

- State (`terraform.tfstate`) is the source of truth Terraform compares
  the world against. Protect it: it can contain secrets (VM admin
  passwords, connection strings) in plaintext.
- **Back it up before risky changes**: `cp terraform.tfstate
  terraform.tfstate.bak`. `terraform state pull > backup.json` for remote
  state.
- **Moved/renamed resources**: use `terraform state mv` or the `moved {}`
  block instead of destroy + recreate — renaming in code is not the same
  as replacing in the cloud.
- **Manually-fixed resources**: if someone fixed a thing in the portal,
  `terraform import` the resource (or delete and let Terraform rebuild it)
  so state and reality agree again.
- **Locking**: with local state there is none. With the azurerm backend,
  blob leasing serializes applies automatically — never delete a lease
  manually unless you're sure no apply is running.

## 6. Drift — what it is and how you handle it

Drift is any difference between what Terraform last applied and what
actually exists now: someone opened port 3389 in the portal, resized the
VM by hand, or a policy changed a tag. Detection is cheap:

```bash
# on a schedule (cron / CI): re-run plan and alert if it's non-empty
terraform plan -detailed-exitcode -out=/tmp/drift-check
# exit code 0 = clean, 2 = drift detected, 1 = error
```

What drift means depends on intent:

| Situation | Response |
|---|---|
| Accidental hand-edit (the usual case) | `terraform apply` to converge back to code |
| Intentional hotfix done in the portal | Import it (`terraform import`) or codify it, then apply |
| Change that should NOT exist (security rule widened) | Treat as an incident: investigate first, converge after |

The discipline: the repo is the desired state; anything else is either a
bug or a change request that hasn't been written down yet.

## 7. Secrets — where they go (and don't)

**Never in the repo. Never in state if you can avoid it.**

- **Terraform**: no `password = "..."` literals, no committed
  `.tfvars`. Pass values via environment variables (`TF_VAR_db_password`)
  or a gitignored `terraform.tfvars`. For production, reference Azure Key
  Vault with a `data "azurerm_key_vault_secret"` block — the secret stays
  in the vault, only the *reference* is in code, and even then it lands in
  state (state must be treated as sensitive regardless).
- **Ansible**: encrypt with `ansible-vault` —
  `ansible-vault encrypt_string 's3cret' --name db_password` — and commit
  only the ciphertext. The vault password lives in a password manager or
  CI secret store, never in the repo (`.vault-pass` is gitignored).
- **General rule**: if a value would let someone log in, spend money, or
  read data, it doesn't belong in git. If it ends up in state anyway,
  encrypt/lock down the state backend and rotate the secret.

## 8. Destroy (teardown)

```bash
terraform plan -destroy -out=destroy.plan
terraform apply destroy.plan
```

Destroy is a plan like any other — review it before you apply it. In this
implementation, teardown is how you prove the whole stack is reproducible: `apply` →
verify → `destroy` → `apply` again.

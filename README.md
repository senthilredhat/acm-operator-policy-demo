# ACM OperatorPolicy Demo — Label-Based Group Placement

This repository demonstrates how to use Red Hat Advanced Cluster Management (ACM)
OperatorPolicy to manage the lifecycle of the GitLab operator across multiple
OpenShift clusters using a **label-based group placement** GitOps model.

## Core Concepts

| Object | Role |
|---|---|
| **Policy** | _What_ to install (the GitLab OperatorPolicy) |
| **Placement** | _Where_ to install it (which clusters match a label selector) |
| **PlacementBinding** | _Connects_ a Policy to a Placement |
| **Labels** | _Control_ which clusters fall into each rollout group |

A single group Placement can select **many** managed clusters by label. For
example, all clusters with `environment=qa` and `operators-ready=true` receive
the GitLab OperatorPolicy — no per-cluster duplication is required.

## Architecture

### GitOps Flow

```
Git Repository
  │
  ▼
ACM Channel (acm-operator-policy-demo)
  │
  ▼
Bootstrap (oc apply -k app-of-app-manifest/)
  ├── Top-level subscription → app-of-app-group-subs    (GitLab operator groups)
  └── Cluster subscription  → app-of-app-cluster-subs  (serverless-operator, legacy)
  │
  ▼
Group subscriptions (qa / wave1 / wave2 / prod)
  │  Each subscription syncs one groups/<name>/ folder to the hub
  ▼
groups/qa/
  ├── policy-gitlab-operator     (from components/gitlab-operator)
  ├── placement-gitlab-operator-qa  (matchLabels: environment=qa, operators-ready=true)
  └── binding-gitlab-operator-qa
  │
  ▼
All ManagedClusters whose labels match
  └── GitLab operator installed via OperatorPolicy enforcement
```

### Folder Structure

```
.
├── components/
│   └── gitlab-operator/         # Reusable Policy definition only
│       ├── policy.yaml
│       └── kustomization.yaml
│
├── groups/                       # Label-based rollout groups
│   ├── qa/
│   │   ├── placement.yaml        # selector: environment=qa, operators-ready=true
│   │   ├── placement-binding.yaml
│   │   └── kustomization.yaml
│   ├── wave1/
│   │   ├── placement.yaml        # selector: operator-upgrade-wave=wave1, operators-ready=true
│   │   ├── placement-binding.yaml
│   │   └── kustomization.yaml
│   ├── wave2/
│   │   └── ...
│   └── prod/
│       └── ...
│
├── app-of-app-group-subs/        # Group-level ACM subscriptions (PRIMARY)
│   ├── kustomization.yaml        # CRITICAL: lists qa, wave1, wave2, prod
│   ├── qa/                       # Subscription that deploys groups/qa
│   ├── wave1/
│   ├── wave2/
│   └── prod/
│
├── app-of-app-cluster-subs/      # Cluster-level subscriptions (serverless-operator)
│   ├── kustomization.yaml
│   ├── c01/
│   └── c02/
│
├── clusters/                     # Cluster-specific configs (serverless-operator only)
│   ├── c01/
│   └── c02/
│
├── app-of-app-manifest/          # Bootstrap — one-shot initialization
│   ├── channel/
│   └── initialize-acm-gitops/
│
└── docs/
    ├── operator-upgrade-guide.md
    └── legacy-cluster-specific-placement/  # Archived per-cluster files (reference only)
```

## Label Model

### QA environments

```yaml
matchLabels:
  environment: qa
  operators-ready: "true"
```

### Upgrade waves

```yaml
# wave1
matchLabels:
  operator-upgrade-wave: wave1
  operators-ready: "true"

# wave2
matchLabels:
  operator-upgrade-wave: wave2
  operators-ready: "true"

# prod
matchLabels:
  operator-upgrade-wave: prod
  operators-ready: "true"
```

The `operators-ready: "true"` label acts as a readiness gate — remove it from
a cluster to pause rollout without changing any policy or placement objects.

## Object Names (hub `policies` namespace)

| Group | Placement | PlacementBinding | Policy |
|---|---|---|---|
| qa | `placement-gitlab-operator-qa` | `binding-gitlab-operator-qa` | `policy-gitlab-operator` |
| wave1 | `placement-gitlab-operator-wave1` | `binding-gitlab-operator-wave1` | `policy-gitlab-operator` |
| wave2 | `placement-gitlab-operator-wave2` | `binding-gitlab-operator-wave2` | `policy-gitlab-operator` |
| prod | `placement-gitlab-operator-prod` | `binding-gitlab-operator-prod` | `policy-gitlab-operator` |

The same `policy-gitlab-operator` is shared; each group binds it through its
own unique Placement.

## Prerequisites

- Red Hat Advanced Cluster Management 2.11+ on the hub cluster
- `kubectl` or `oc` CLI configured against the hub
- Managed clusters labelled appropriately (see label model above)

## Setup

### Step 1: Bootstrap ACM GitOps (one-shot)

```bash
oc apply -k app-of-app-manifest/
```

This creates:
- `acm-operator-policy-demo-ns` namespace and Git Channel
- `policies` namespace with **ManagedClusterSetBinding** for the `global` cluster set
- ClusterRoleBinding granting subscription-admin privileges
- Top-level subscription (`cluster-subscriptions`) → `app-of-app-cluster-subs`
- Group subscription (`group-subscriptions`) → `app-of-app-group-subs`

Verify:

```bash
oc get channel -n acm-operator-policy-demo-ns
oc get subscription -n policies
oc get managedclustersetbinding -n policies
```

### Step 2: Label managed clusters

```bash
# QA clusters
oc label managedcluster c01 environment=qa operators-ready=true --overwrite
oc label managedcluster c02 environment=qa operators-ready=true --overwrite

# Wave-based clusters (when ready for upgrade rollout)
oc label managedcluster c03 operator-upgrade-wave=wave1 operators-ready=true --overwrite
oc label managedcluster c04 operator-upgrade-wave=wave2 operators-ready=true --overwrite
oc label managedcluster c05 operator-upgrade-wave=prod  operators-ready=true --overwrite
```

### Step 3: Verify Placement decisions

```bash
oc get placement -n policies
oc describe placement placement-gitlab-operator-qa -n policies
oc get placementdecision -n policies
```

Expected: `placement-gitlab-operator-qa` selects both c01 and c02 because both
carry `environment=qa` — one placement, multiple clusters, no duplication.

### Step 4: Verify Policy propagation

```bash
oc get policy -n policies
oc describe policy policy-gitlab-operator -n policies

# Compliance status
oc get policy policy-gitlab-operator -n policies -o jsonpath='{.status.compliant}'
```

### Step 5: Verify operator installation on a managed cluster

```bash
# On the managed cluster (or via ACM console):
oc get subscription -n gitlab-system
oc get csv -n gitlab-system
oc get pods -n gitlab-system
```

## Validating the Repository Structure

```bash
./validate.sh
```

The script:
- Renders each `groups/<name>` kustomization and confirms it builds
- Verifies policy name is `policy-gitlab-operator`
- Checks Placement names match PlacementBinding references within each group
- Verifies group subscription git-paths are correct
- Checks all kustomization.yaml files exist at subscription targets

Preview rendered output manually:

```bash
kubectl kustomize groups/qa
kubectl kustomize groups/wave1
kubectl kustomize app-of-app-group-subs
```

## Rollout Workflow

### Initial QA validation

1. Label QA clusters with `environment=qa` and `operators-ready=true`
2. Observe `placement-gitlab-operator-qa` decisions include all QA clusters
3. Confirm `policy-gitlab-operator` propagates and GitLab operator installs

### Phased production rollout

```bash
# Promote wave1 clusters
oc label managedcluster c03 operator-upgrade-wave=wave1 operators-ready=true --overwrite

# After wave1 is healthy, promote wave2
oc label managedcluster c04 operator-upgrade-wave=wave2 operators-ready=true --overwrite

# After wave2 is healthy, promote prod
oc label managedcluster c05 operator-upgrade-wave=prod operators-ready=true --overwrite
```

### Pause rollout for a cluster

```bash
# Remove operators-ready gate to pause without changing any policy
oc label managedcluster c04 operators-ready- --overwrite
```

## Adding a New Group

1. Create `groups/<name>/placement.yaml` with the appropriate label selector
2. Create `groups/<name>/placement-binding.yaml` referencing `policy-gitlab-operator`
3. Create `groups/<name>/kustomization.yaml` including `../../components/gitlab-operator`
4. Create `app-of-app-group-subs/<name>/` with namespace, placement, subscription, application, kustomization
5. Add `<name>` to `app-of-app-group-subs/kustomization.yaml` resources list
6. Commit and push — ACM picks it up automatically

## Adding a New Operator Component

1. Create `components/<operator>/policy.yaml` and `kustomization.yaml`
2. Add a `placement.yaml` and `placement-binding.yaml` to the appropriate group folders
3. Update each group's `kustomization.yaml` to include the new component

## Upgrading the Operator

See [docs/operator-upgrade-guide.md](docs/operator-upgrade-guide.md).

Quick example — pin to a specific CSV:

```bash
# Edit the component policy
vi components/gitlab-operator/policy.yaml
# Add under subscription:
#   startingCSV: gitlab-operator-kubernetes.v1.2.3

git add components/gitlab-operator/policy.yaml
git commit -m "Pin GitLab operator to v1.2.3"
git push origin main
```

The change is automatically picked up by all four group subscriptions.

## Troubleshooting

### Placement selects no clusters

```bash
oc get placement placement-gitlab-operator-qa -n policies -o yaml | grep -A 10 status
oc get managedclustersetbinding -n policies
```

The `global` ManagedClusterSetBinding must exist in the `policies` namespace for
Placements there to see managed clusters. It is created by the bootstrap.

### No PlacementDecisions

```bash
oc get placementdecision -n policies -l cluster.open-cluster-management.io/placement=placement-gitlab-operator-qa
```

If empty, verify the managed cluster carries the expected labels:

```bash
oc get managedcluster c01 --show-labels
```

### Group subscription not syncing

```bash
# Top-level group subscription
oc describe subscription group-subscriptions -n policies

# Individual group subscription
oc describe subscription gitlab-qa-group-apps -n gitlab-qa
```

### Policy non-compliant

```bash
oc get policy policy-gitlab-operator -n policies -o yaml | grep -A 20 status
oc get events -n policies --field-selector involvedObject.name=policy-gitlab-operator
```

## Key Design Principles

1. One Placement per logical rollout group, not per cluster.
2. Cluster selection is controlled entirely by ManagedCluster labels.
3. `components/gitlab-operator/` contains only the reusable Policy — no Placement or PlacementBinding.
4. All hub-side governance objects live in the `policies` namespace.
5. Object names are unique in the hub namespace — no suffixing required.
6. The `operators-ready: "true"` label acts as a per-cluster readiness gate.

## Resources

- [Getting started with OperatorPolicy](https://developers.redhat.com/articles/2024/08/08/getting-started-operatorpolicy)
- [Use OperatorPolicy to manage Kubernetes-native applications](https://developers.redhat.com/articles/2024/05/14/use-operatorpolicy-manage-kubernetes-native-applications)
- [ACM Governance Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/governance/index)
- [Open Cluster Management Policies](https://open-cluster-management.io/docs/getting-started/integration/policy-controllers/policy/)

## License

Demonstration repository for educational purposes.

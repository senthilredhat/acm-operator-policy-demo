# ACM OperatorPolicy Demo

This repository demonstrates how to use Red Hat Advanced Cluster Management (ACM) OperatorPolicy to manage the lifecycle of the GitLab operator across multiple OpenShift clusters using a GitOps approach.

## Overview

This demo showcases:
- **OperatorPolicy**: Managing operator installation and upgrades declaratively
- **ACM Policies**: Enforcing operator configurations across clusters
- **GitOps Pattern**: Using ACM Application/Subscription to pull configurations from Git
- **Kustomize Layers**: Organizing configurations with components, groups, and cluster-specific overlays

## Architecture

### GitOps Flow - Layered App-of-Apps Pattern

```
┌─────────────────────────────────────────────────────────┐
│ Git Repository (this repo)                              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ ACM Channel (acm-operator-policy-demo)                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Top-level Subscription (namespace: policies)            │
│ git-path: app-of-app-cluster-subs                       │
└────────────────────┬────────────────────────────────────┘
                     │
                     ├─► Creates cluster subscriptions
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Cluster c01 Subscription (namespace: c01)               │
│ git-path: clusters/c01                                  │
└────────────────────┬────────────────────────────────────┘
                     │
                     ├─► Deploys all components configured for c01:
                     │
                     ├─► clusters/c01/common/
                     │   └─► Placement (environment=qa)
                     │
                     ├─► clusters/c01/gitlab-operator/
                     │   ├─► components/gitlab-operator/policy.yaml
                     │   └─► placement-binding.yaml
                     │
                     └─► Future: clusters/c01/gov1/, gov2/, etc.
                     
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Policy Propagated to Managed Cluster (c01)              │
│ via Placement + PlacementBinding                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ OperatorPolicy Enforced                                 │
│ GitLab operator installed/managed on cluster c01        │
└─────────────────────────────────────────────────────────┘
```

### Folder Structure

```
.
├── components/                  # Base policy definitions
│   └── gitlab-operator/        # OperatorPolicy definition
├── groups/                      # Kustomize components for cluster groups
│   ├── all/                    # Common to all clusters
│   └── qa/                     # QA-specific configuration
├── clusters/                    # Cluster-specific configurations
│   └── c01/
│       ├── kustomization.yaml  # CRITICAL: Lists all components to deploy for c01
│       ├── common/             # Shared placement, references groups
│       │   ├── placement.yaml
│       │   └── kustomization.yaml
│       └── gitlab-operator/    # Component-specific config
│           ├── placement-binding.yaml
│           └── kustomization.yaml (references ../../../components/gitlab-operator)
├── app-of-app-cluster-subs/    # Cluster-level subscriptions
│   ├── kustomization.yaml      # CRITICAL: Lists all cluster subscriptions (c01, future: c02, etc.)
│   └── c01/                    # Subscription for cluster c01
│       ├── namespace.yaml      # Creates 'c01' namespace
│       ├── application.yaml
│       ├── subscription.yaml   # Points to clusters/c01
│       └── kustomization.yaml
├── app-of-app-manifest/         # Bootstrap - one-shot initialization
│   ├── kustomization.yaml      # Deploys channel + initialize-acm-gitops
│   ├── channel/                # Git channel definition
│   └── initialize-acm-gitops/  # Top-level subscription (points to app-of-app-cluster-subs)
└── docs/                        # Documentation
```

### Architecture Layers

This repository uses a 3-layer app-of-apps architecture:

1. **Components Layer** (`components/`): Contains actual policy manifests
   - Reusable policy definitions
   - No cluster-specific configuration

2. **Cluster Layer** (`clusters/c01/`): Cluster-specific configurations
   - `common/`: Shared resources (placement)
   - `gitlab-operator/`: References component + placement-binding
   - Future: `gov1/`, `gov2/`, etc.

3. **App-of-App Layer** (`app-of-app-cluster-subs/`): Per-cluster subscriptions
   - Each cluster folder contains a subscription pointing to `clusters/<cluster-name>`
   - Automatically deploys all components configured for that cluster

### Components

1. **OperatorPolicy**: Defines the GitLab operator subscription spec
2. **Placement**: Selects clusters with label `environment=qa` (in `clusters/c01/common/`)
3. **PlacementBinding**: Links the policy to the placement (in `clusters/c01/gitlab-operator/`)
4. **Channel**: Points to this Git repository
5. **Top-level Subscription**: Pulls cluster subscriptions from `app-of-app-cluster-subs`
6. **Cluster Subscription**: Pulls all components from `clusters/c01`

## Prerequisites

- Red Hat Advanced Cluster Management 2.11+ installed on hub cluster
- Hub cluster (`mocp`) with ACM operator
- At least one managed cluster (`c01`) with label `environment=qa`
- `oc` CLI configured and logged into the hub cluster
- Git repository access

## Setup Instructions

### Step 1: Verify Cluster Setup

Ensure your managed cluster has the correct label:

```bash
# List managed clusters
oc get managedclusters

# Verify c01 has environment=qa label
oc get managedcluster c01 --show-labels

# Add label if missing
oc label managedcluster c01 environment=qa
```

### Step 2: Initialize ACM GitOps (One-Shot Bootstrap)

Deploy all bootstrap resources in one command:

```bash
oc apply -k app-of-app-manifest/
```

This creates:
- `acm-operator-policy-demo-ns` namespace and Git channel
- `policies` namespace
- Application and Subscription pointing to `app-of-app-cluster-subs`
- Placement targeting the hub cluster (local-cluster)

Verify the resources were created:

```bash
# Verify channel
oc get channel -n acm-operator-policy-demo-ns

# Verify top-level subscription
oc get subscription -n policies
oc get application -n policies
```

### Step 3: Verify Cluster Subscription Deployment

Wait for the subscription to sync (may take 1-2 minutes):

```bash
# Check top-level subscription status
oc get subscription -n policies

# Check application
oc get application -n policies

# Verify cluster c01 namespace and subscription were created
oc get namespace c01
oc get subscription -n c01
oc get application -n c01

# Verify policy was created
oc get policy -n policies

# Check placement (in policies namespace, created from clusters/c01/common/)
oc get placement -n policies

# Verify placement binding
oc get placementbinding -n policies
```

Expected policy name: `gitlab-operator-policy-all-qa-c01`

### Step 4: Verify Policy Propagation

Check that the policy is compliant on the managed cluster:

```bash
# Check policy status
oc get policy gitlab-operator-policy-all-qa-c01 -n policies

# Get detailed compliance status
oc describe policy gitlab-operator-policy-all-qa-c01 -n policies

# View policy decisions (which clusters matched)
oc get placementdecision -n policies
```

### Step 5: Verify Operator Installation on Managed Cluster (c01)

The OperatorPolicy will install the GitLab operator on cluster c01:

```bash
# Switch context to c01 or use ACM to check:

# Verify subscription created
oc get subscription -n gitlab-system

# Check ClusterServiceVersion (CSV)
oc get csv -n gitlab-system

# Verify operator is installed
oc get operators

# Check operator pods
oc get pods -n gitlab-system
```

## Validating the Setup

### Test Policy Compliance

```bash
# Policy should show as compliant
oc get policy gitlab-operator-policy-all-qa-c01 -n policies -o jsonpath='{.status.compliant}'

# Should return: Compliant
```

### Test GitOps Synchronization

1. Make a change to [`components/gitlab-operator/policy.yaml`](components/gitlab-operator/policy.yaml)
2. Commit and push to the Git repository
3. Wait for the cluster subscription to sync:
   ```bash
   # Watch cluster c01 subscription
   oc get subscription -n c01 -w
   ```
4. Verify the policy was updated:
   ```bash
   oc get policy gitlab-operator-policy-all-qa-c01 -n policies -o yaml
   ```

## Upgrading the Operator

See the [Operator Upgrade Guide](docs/operator-upgrade-guide.md) for detailed instructions on:
- Automatic upgrades
- Pinning to specific versions
- Monitoring upgrade status
- Rollback procedures

Quick example:

```bash
# Edit the policy to pin to a specific version
vi components/gitlab-operator/policy.yaml

# Add startingCSV field:
# subscription:
#   startingCSV: gitlab-operator-kubernetes.v1.2.3

# Commit and push
git add components/gitlab-operator/policy.yaml
git commit -m "Pin GitLab operator to v1.2.3"
git push origin main
```

## Troubleshooting

### Policy Shows Non-Compliant

```bash
# Get violation details
oc get policy gitlab-operator-policy-all-qa-c01 -n policies -o yaml | grep -A 20 status

# Check policy events
oc get events -n policies --field-selector involvedObject.name=gitlab-operator-policy-all-qa-c01
```

### Subscription Not Syncing

```bash
# Check top-level subscription (app-of-app-cluster-subs)
oc describe subscription -n policies cluster-subscriptions

# Check cluster c01 subscription
oc describe subscription -n c01 c01-cluster-apps

# Force manual reconciliation on cluster subscription
oc annotate subscription c01-cluster-apps -n c01 \
  apps.open-cluster-management.io/manual-refresh-time="$(date +%s)"
```

### Operator Not Installing on Managed Cluster

```bash
# Check policy propagation
oc get policy -A | grep gitlab-operator

# On managed cluster, check for policy
oc get policy -n c01

# Check OperatorPolicy status
oc get operatorpolicy -A
```

## Customization

### Adding a New Component to Cluster c01

When you want to add a new governance policy (e.g., `gov1`):

1. **Create the component** with policy manifests:
   ```bash
   mkdir -p components/gov1
   # Add your policy.yaml and kustomization.yaml
   ```

2. **Add to cluster c01**:
   ```bash
   mkdir -p clusters/c01/gov1
   ```

3. **Create cluster configuration** (`clusters/c01/gov1/kustomization.yaml`):
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   components:
     - ../common  # Shares the placement
   
   resources:
     - ../../../components/gov1
     - placement-binding.yaml  # Component-specific binding
   
   namespace: policies
   ```

4. **Create placement-binding** (`clusters/c01/gov1/placement-binding.yaml`) to bind your policy to the shared placement

5. **Update `clusters/c01/kustomization.yaml`** to include the new component:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   resources:
     - gitlab-operator
     - gov1  # Add new component here
   ```

6. Commit and push - the cluster c01 subscription will automatically pick it up!

### Adding More Clusters

To add cluster c02:

1. **Create cluster subscription** folder:
   ```bash
   mkdir -p app-of-app-cluster-subs/c02
   ```

2. **Create subscription files** (copy from c01 and modify):
   ```bash
   # namespace.yaml, application.yaml, subscription.yaml, kustomization.yaml
   # Update names to c02 and git-path to clusters/c02
   ```

3. **Update `app-of-app-cluster-subs/kustomization.yaml`** to include c02:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   resources:
     - c01
     - c02  # Add new cluster here
   ```

4. **Create cluster configuration**:
   ```bash
   mkdir -p clusters/c02
   # Create clusters/c02/kustomization.yaml listing components
   mkdir -p clusters/c02/common
   mkdir -p clusters/c02/gitlab-operator
   # Add placement.yaml, placement-binding.yaml, kustomization.yaml
   ```

5. Commit and push - the top-level subscription will deploy c02!

### Creating Production Policies

1. Create a new group: `groups/prod/`
2. Create cluster-specific overlays: `clusters/prod01/`
3. Create app-of-app subscription: `app-of-app-cluster-subs/prod01/`
4. Reference production cluster labels in `clusters/prod01/common/placement.yaml`

### Changing Operator Configuration

Edit [`components/gitlab-operator/policy.yaml`](components/gitlab-operator/policy.yaml) to modify:
- Operator channel (stable, fast, etc.)
- Installation namespace
- Operator source catalog
- Version pinning

## Kustomize Structure Explanation

This repo uses a 3-layer kustomize architecture:

### Layer 1: Components (`components/`)
Base policy definitions, reusable across clusters:
```bash
components/gitlab-operator/
├── policy.yaml         # OperatorPolicy definition
└── kustomization.yaml
```

### Layer 2: Cluster Configurations (`clusters/c01/`)
Cluster-specific configurations that reference components:
```bash
clusters/c01/
├── kustomization.yaml       # CRITICAL: Lists components to deploy (gitlab-operator, future: gov1, etc.)
├── common/
│   ├── placement.yaml       # Shared by all components in this cluster
│   └── kustomization.yaml   # References groups/all, groups/qa
└── gitlab-operator/
    ├── placement-binding.yaml   # Binds policy to placement
    └── kustomization.yaml       # References ../common and ../../../components/gitlab-operator
```

**Important**: The `clusters/c01/kustomization.yaml` is the entry point for the cluster subscription. It lists all component folders to deploy.

### Layer 3: App-of-App Subscriptions (`app-of-app-cluster-subs/`)
Per-cluster subscriptions that deploy everything for that cluster:
```bash
app-of-app-cluster-subs/
├── kustomization.yaml  # CRITICAL: Lists all clusters (c01, future: c02, etc.)
└── c01/
    ├── namespace.yaml      # Creates c01 namespace
    ├── application.yaml    # Application wrapper
    ├── subscription.yaml   # Points to clusters/c01
    └── kustomization.yaml
```

**Important**: The `app-of-app-cluster-subs/kustomization.yaml` is the entry point for the top-level subscription. It lists all cluster subscription folders.

### Bootstrap Layer (`app-of-app-manifest/`)
One-shot initialization of the entire GitOps system:
```bash
app-of-app-manifest/
├── kustomization.yaml          # Single entry point - deploys everything below
├── channel/                    # Git channel pointing to this repo
└── initialize-acm-gitops/      # Top-level subscription pointing to app-of-app-cluster-subs
```

### Groups Layer (`groups/`)
Kustomize components for reusable configurations:
- `groups/all/`: Common to all clusters
- `groups/qa/`: QA-specific configuration

To build and preview the final manifests:

```bash
# Preview what will be deployed for cluster c01
oc kustomize clusters/c01/gitlab-operator/

# Preview cluster c01 app-of-app subscription
oc kustomize app-of-app-cluster-subs/c01/

# Validate the kustomization
oc kustomize clusters/c01/gitlab-operator/ | oc apply --dry-run=client -f -
```

## Validation Script

**Important**: Run the validation script whenever you make changes to the structure:

```bash
./validate.sh
```

This script validates:
- All kustomize builds complete successfully
- Subscription git-paths point to correct directories
- **All subscription targets have kustomization.yaml files** (CRITICAL)
- PlacementBinding correctly references the Placement
- Resource naming consistency across layers

### Critical Files - Subscription Targets

These files MUST exist because subscriptions point to their directories:

1. **`app-of-app-cluster-subs/kustomization.yaml`**
   - Target of: Top-level subscription (`git-path: app-of-app-cluster-subs`)
   - Lists: All cluster subscription folders (c01, c02, etc.)

2. **`clusters/c01/kustomization.yaml`**
   - Target of: Cluster c01 subscription (`git-path: clusters/c01`)
   - Lists: All components to deploy for c01 (gitlab-operator, gov1, etc.)

## Benefits of This Architecture

### Scalability
- **Easy to add new components**: Just create a folder under `clusters/c01/new-component/` and reference the component
- **Easy to add new clusters**: Copy the app-of-app subscription structure and cluster configuration
- **No changes to top-level**: The top-level subscription automatically picks up new clusters

### Maintainability
- **Separation of concerns**: Components, cluster configs, and subscriptions are isolated
- **Shared resources**: Placement is shared via `clusters/c01/common/`, reducing duplication
- **Consistent pattern**: All clusters follow the same structure

### Flexibility
- **Per-cluster customization**: Each cluster can have different components
- **Per-component customization**: Each component can have cluster-specific overrides
- **Layered composition**: Groups provide reusable configurations across clusters

## Key Features Demonstrated

1. **Layered App-of-Apps Pattern**: Multi-level GitOps subscriptions for scalable deployments
2. **OperatorPolicy v1beta1**: Modern operator lifecycle management
3. **Placement v1beta1**: Modern cluster selection API
4. **GitOps Pattern**: Infrastructure as code with Git as source of truth
5. **Kustomize Components**: Composable configuration management
6. **Multi-cluster Management**: Single policy definition, multiple clusters
7. **Shared Resources**: Common placement across components per cluster

## Resources and References

- [Getting started with OperatorPolicy](https://developers.redhat.com/articles/2024/08/08/getting-started-operatorpolicy)
- [Use OperatorPolicy to manage Kubernetes-native applications](https://developers.redhat.com/articles/2024/05/14/use-operatorpolicy-manage-kubernetes-native-applications)
- [ACM Governance Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/governance/index)
- [Open Cluster Management Policies](https://open-cluster-management.io/docs/getting-started/integration/policy-controllers/policy/)

## License

This is a demonstration repository for educational purposes.

## Contributing

This is a demo repository. For issues or questions about ACM OperatorPolicy, please refer to the official Red Hat ACM documentation.

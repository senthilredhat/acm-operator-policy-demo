# ACM OperatorPolicy Demo

This repository demonstrates how to use Red Hat Advanced Cluster Management (ACM) OperatorPolicy to manage the lifecycle of the GitLab operator across multiple OpenShift clusters using a GitOps approach.

## Overview

This demo showcases:
- **OperatorPolicy**: Managing operator installation and upgrades declaratively
- **ACM Policies**: Enforcing operator configurations across clusters
- **GitOps Pattern**: Using ACM Application/Subscription to pull configurations from Git
- **Kustomize Layers**: Organizing configurations with components, groups, and cluster-specific overlays

## Architecture

### GitOps Flow

```
Git Repository (this repo)
    ↓
ACM Channel (Git source)
    ↓
ACM Subscription (policies/gitlab-operator path)
    ↓
Policy Created on Hub Cluster
    ↓
Placement (targets environment=qa clusters)
    ↓
Policy Propagated to Managed Cluster (c01)
    ↓
OperatorPolicy Enforced (GitLab operator installed/managed)
```

### Folder Structure

```
.
├── components/              # Base resources
│   └── gitlab-operator/    # OperatorPolicy definition
├── groups/                  # Kustomize components for cluster groups
│   ├── all/                # Common to all clusters
│   └── qa/                 # QA-specific configuration
├── clusters/                # Cluster-specific overlays
│   └── c01/
│       ├── common/         # References groups
│       └── gitlab-operator/# Builds the final policy
├── policies/                # Placement and binding
│   └── gitlab-operator/
├── app-of-app-manifest/     # Bootstrap resources
│   ├── channel/            # Git channel
│   └── policy-deployment/  # App-of-apps subscription
└── docs/                    # Documentation
```

### Components

1. **OperatorPolicy**: Defines the GitLab operator subscription spec
2. **Placement**: Selects clusters with label `environment=qa`
3. **PlacementBinding**: Links the policy to the placement
4. **Channel**: Points to this Git repository
5. **Subscription**: Pulls policy from the `policies/gitlab-operator` path

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

### Step 2: Apply Channel Configuration

Create the Git channel that points to this repository:

```bash
oc apply -k app-of-app-manifest/channel/
```

Verify the channel is created:

```bash
oc get channel -n acm-operator-policy-demo-ns
```

### Step 3: Deploy the Policy via GitOps

Deploy the app-of-apps subscription that will pull the policy from Git:

```bash
oc apply -k app-of-app-manifest/policy-deployment/
```

This creates:
- `policies` namespace
- Application resource
- Subscription pointing to `policies/gitlab-operator` Git path
- Placement targeting the hub cluster (local-cluster)

### Step 4: Verify Policy Deployment

Wait for the subscription to sync (may take 1-2 minutes):

```bash
# Check subscription status
oc get subscription -n policies

# Check application
oc get application -n policies

# Verify policy was created
oc get policy -n policies

# Check placement
oc get placement -n policies

# Verify placement binding
oc get placementbinding -n policies
```

Expected policy name: `gitlab-operator-policy-qa-c01`

### Step 5: Verify Policy Propagation

Check that the policy is compliant on the managed cluster:

```bash
# Check policy status
oc get policy gitlab-operator-policy-qa-c01 -n policies

# Get detailed compliance status
oc describe policy gitlab-operator-policy-qa-c01 -n policies

# View policy decisions (which clusters matched)
oc get placementdecision -n policies
```

### Step 6: Verify Operator Installation on Managed Cluster (c01)

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
oc get policy gitlab-operator-policy-qa-c01 -n policies -o jsonpath='{.status.compliant}'

# Should return: Compliant
```

### Test GitOps Synchronization

1. Make a change to [`components/gitlab-operator/policy.yaml`](components/gitlab-operator/policy.yaml)
2. Commit and push to the Git repository
3. Wait for the subscription to sync (check with `-w` flag):
   ```bash
   oc get subscription -n policies gitlab-operator-policy-subscription -w
   ```
4. Verify the policy was updated:
   ```bash
   oc get policy gitlab-operator-policy-qa-c01 -n policies -o yaml
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
oc get policy gitlab-operator-policy-qa-c01 -n policies -o yaml | grep -A 20 status

# Check policy events
oc get events -n policies --field-selector involvedObject.name=gitlab-operator-policy-qa-c01
```

### Subscription Not Syncing

```bash
# Check subscription status
oc describe subscription -n policies gitlab-operator-policy-subscription

# Force manual reconciliation
oc annotate subscription gitlab-operator-policy-subscription -n policies \
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

### Adding More Clusters

1. Label additional managed clusters with `environment=qa`:
   ```bash
   oc label managedcluster c02 environment=qa
   ```

2. The policy will automatically propagate to newly labeled clusters

### Creating Production Policies

1. Create a new group: `groups/prod/`
2. Create cluster-specific overlays: `clusters/c02/gitlab-operator/`
3. Create new policy in `policies/` with production placement
4. Reference production cluster labels in placement

### Changing Operator Configuration

Edit [`components/gitlab-operator/policy.yaml`](components/gitlab-operator/policy.yaml) to modify:
- Operator channel (stable, fast, etc.)
- Installation namespace
- Operator source catalog
- Version pinning

## Kustomize Structure Explanation

This repo uses kustomize layering:

- **Components Layer** (`components/`): Base OperatorPolicy definitions
- **Groups Layer** (`groups/`): Reusable configurations (all, qa, prod)
- **Clusters Layer** (`clusters/`): Cluster-specific customizations
- **Policies Layer** (`policies/`): Combines everything + adds Placement

To build and preview the final manifests:

```bash
# Preview what will be deployed
oc kustomize policies/gitlab-operator/

# Validate the kustomization
oc kustomize policies/gitlab-operator/ | oc apply --dry-run=client -f -
```

## Key Features Demonstrated

1. **OperatorPolicy v1beta1**: Modern operator lifecycle management
2. **Placement v1beta1**: Modern cluster selection API
3. **GitOps Pattern**: Infrastructure as code with Git as source of truth
4. **Kustomize Components**: Composable configuration management
5. **App-of-Apps Pattern**: Bootstrapping policies via ACM Subscriptions
6. **Multi-cluster Management**: Single policy definition, multiple clusters

## Resources and References

- [Getting started with OperatorPolicy](https://developers.redhat.com/articles/2024/08/08/getting-started-operatorpolicy)
- [Use OperatorPolicy to manage Kubernetes-native applications](https://developers.redhat.com/articles/2024/05/14/use-operatorpolicy-manage-kubernetes-native-applications)
- [ACM Governance Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/governance/index)
- [Open Cluster Management Policies](https://open-cluster-management.io/docs/getting-started/integration/policy-controllers/policy/)

## License

This is a demonstration repository for educational purposes.

## Contributing

This is a demo repository. For issues or questions about ACM OperatorPolicy, please refer to the official Red Hat ACM documentation.

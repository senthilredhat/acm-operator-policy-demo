# GitLab Operator Upgrade Guide

This guide explains how to upgrade the GitLab operator version using ACM OperatorPolicy.

## Overview

The GitLab operator is managed through an OperatorPolicy defined in [`components/gitlab-operator/policy.yaml`](../components/gitlab-operator/policy.yaml). OperatorPolicy provides declarative operator lifecycle management, including version control and upgrades.

## Understanding OperatorPolicy Version Management

### Automatic Upgrades (Default Behavior)

By default, the OperatorPolicy configuration uses:
- **Channel**: `stable` - Receives updates from the stable channel
- **Approval Mode**: Automatic (default for most operators)

With this configuration, the operator will automatically upgrade to newer versions within the `stable` channel as they become available.

### Pinning to a Specific Version

To pin the operator to a specific version and prevent automatic upgrades, add the `startingCSV` field to the subscription spec in the OperatorPolicy.

## How to Upgrade the Operator

### Method 1: Automatic Upgrades (Recommended for QA)

1. Keep the current configuration without `startingCSV`
2. The operator will automatically upgrade when new versions are released to the `stable` channel
3. Monitor the upgrade status (see Monitoring section below)

### Method 2: Manual Version Control

#### Step 1: Identify Available Versions

On the hub cluster, check available operator versions:

```bash
oc get packagemanifest gitlab-operator-kubernetes -n openshift-marketplace -o jsonpath='{.status.channels[?(@.name=="stable")].currentCSV}'
```

To see all available versions in the stable channel:

```bash
oc get packagemanifest gitlab-operator-kubernetes -n openshift-marketplace -o jsonpath='{.status.channels[?(@.name=="stable")].entries[*].name}' | tr ' ' '\n'
```

#### Step 2: Update the Policy

Edit [`components/gitlab-operator/policy.yaml`](../components/gitlab-operator/policy.yaml) and add the `startingCSV` field to the OperatorPolicy subscription spec:

```yaml
spec:
  subscription:
    name: gitlab-operator-kubernetes
    namespace: gitlab-system
    channel: stable
    source: community-operators
    sourceNamespace: openshift-marketplace
    startingCSV: gitlab-operator-kubernetes.v1.2.3  # Pin to specific version
```

#### Step 3: Commit and Push Changes

```bash
git add components/gitlab-operator/policy.yaml
git commit -m "Upgrade GitLab operator to version v1.2.3"
git push origin main
```

#### Step 4: Verify GitOps Synchronization

The ACM Subscription on the hub cluster will automatically detect the Git changes:

```bash
# Watch the subscription sync status
oc get subscription -n policies gitlab-operator-policy-subscription -w

# Check if the policy has been updated
oc get policy -n policies gitlab-operator-policy-qa-c01 -o yaml
```

#### Step 5: Monitor Policy Propagation

The policy will be propagated to managed clusters (c01) based on the placement:

```bash
# Check policy compliance status
oc get policy -n policies gitlab-operator-policy-qa-c01 -o jsonpath='{.status.compliant}'

# Get detailed status from all clusters
oc describe policy -n policies gitlab-operator-policy-qa-c01
```

#### Step 6: Verify Operator Upgrade on Spoke Cluster (c01)

Switch to the spoke cluster context or use ACM to verify:

```bash
# Check the ClusterServiceVersion (CSV) - this shows the installed operator version
oc get csv -n gitlab-system

# Check the subscription
oc get subscription -n gitlab-system gitlab-operator-kubernetes -o yaml

# View the install plan
oc get installplan -n gitlab-system

# Check operator pods
oc get pods -n gitlab-system
```

## Monitoring Upgrade Status

### From the Hub Cluster

```bash
# Check overall policy compliance
oc get policy -n policies

# Get detailed policy status
oc get policy gitlab-operator-policy-qa-c01 -n policies -o yaml | grep -A 20 status

# View policy events
oc get events -n policies --field-selector involvedObject.name=gitlab-operator-policy-qa-c01
```

### From ACM Console

1. Navigate to **Governance** → **Policies**
2. Find `gitlab-operator-policy-qa-c01`
3. View compliance status per cluster
4. Click on the policy to see detailed status and violations

### From Spoke Cluster (c01)

```bash
# Check CSV status - look for PHASE: Succeeded
oc get csv -n gitlab-system

# Check subscription status
oc get subscription gitlab-operator-kubernetes -n gitlab-system -o jsonpath='{.status.installedCSV}'

# View operator events
oc get events -n gitlab-system --field-selector involvedObject.kind=Subscription
```

## Example: Upgrading from v1.0.0 to v1.2.0

### Scenario
Currently running GitLab operator v1.0.0, want to upgrade to v1.2.0.

### Steps

1. **Check current version on c01**:
   ```bash
   oc get csv -n gitlab-system -o jsonpath='{.items[0].spec.version}'
   ```

2. **Update the policy** in `components/gitlab-operator/policy.yaml`:
   ```yaml
   subscription:
     name: gitlab-operator-kubernetes
     namespace: gitlab-system
     channel: stable
     source: community-operators
     sourceNamespace: openshift-marketplace
     startingCSV: gitlab-operator-kubernetes.v1.2.0
   ```

3. **Commit and push**:
   ```bash
   git add components/gitlab-operator/policy.yaml
   git commit -m "Upgrade GitLab operator from v1.0.0 to v1.2.0"
   git push origin main
   ```

4. **Monitor the upgrade** (it may take 1-5 minutes for GitOps sync):
   ```bash
   # Watch policy compliance
   watch -n 5 'oc get policy gitlab-operator-policy-qa-c01 -n policies -o jsonpath="{.status.compliant}"'
   
   # On spoke cluster, watch CSV
   watch -n 5 'oc get csv -n gitlab-system'
   ```

5. **Verify upgrade completed**:
   ```bash
   oc get csv -n gitlab-system -o jsonpath='{.items[0].spec.version}'
   # Should show: 1.2.0
   ```

## Rollback Procedures

### Rolling Back to a Previous Version

If an upgrade causes issues, you can rollback by updating the `startingCSV` to the previous version:

1. Edit `components/gitlab-operator/policy.yaml`:
   ```yaml
   subscription:
     startingCSV: gitlab-operator-kubernetes.v1.0.0  # Previous working version
   ```

2. Commit and push:
   ```bash
   git add components/gitlab-operator/policy.yaml
   git commit -m "Rollback GitLab operator to v1.0.0"
   git push origin main
   ```

3. Monitor the rollback using the same monitoring steps as upgrades

**Note**: Not all operators support downgrading. Check the operator documentation before attempting a rollback.

## Best Practices

### 1. Test in QA First
- The current configuration targets clusters with `environment=qa` label
- Always test upgrades in QA environment before promoting to production
- Create separate policies for production with different placement rules

### 2. Gradual Rollouts
For production, consider:
- Using multiple policies with different placements
- Upgrading a subset of clusters first
- Monitoring for issues before proceeding to remaining clusters

### 3. Change Management
- Document the reason for each upgrade in the git commit message
- Include the CVE or feature requirement that triggered the upgrade
- Notify stakeholders before major version upgrades

### 4. Monitoring
- Set up alerts for policy violations
- Monitor operator pod health after upgrades
- Watch for application-specific issues that may arise from operator changes

### 5. Version Pinning
- In production, use `startingCSV` to pin to specific versions
- Only upgrade after testing in lower environments
- Keep a record of tested and approved operator versions

## Troubleshooting

### Policy Shows Non-Compliant

```bash
# Get detailed violation message
oc get policy gitlab-operator-policy-qa-c01 -n policies -o jsonpath='{.status.status[0].compliant}'

# Check policy details
oc describe policy gitlab-operator-policy-qa-c01 -n policies
```

### Operator Not Upgrading

```bash
# Check subscription status on spoke
oc get subscription gitlab-operator-kubernetes -n gitlab-system -o yaml

# Check install plan
oc get installplan -n gitlab-system

# Check operator events
oc get events -n gitlab-system --sort-by='.lastTimestamp'
```

### GitOps Subscription Not Syncing

```bash
# Check subscription on hub
oc get subscription -n policies gitlab-operator-policy-subscription -o yaml

# Check for errors
oc describe subscription -n policies gitlab-operator-policy-subscription

# Manually trigger reconciliation
oc annotate subscription gitlab-operator-policy-subscription -n policies \
  apps.open-cluster-management.io/manual-refresh-time="$(date +%s)"
```

## References

- [Getting started with OperatorPolicy - Red Hat Developer](https://developers.redhat.com/articles/2024/08/08/getting-started-operatorpolicy)
- [Use OperatorPolicy to manage Kubernetes-native applications - Red Hat Developer](https://developers.redhat.com/articles/2024/05/14/use-operatorpolicy-manage-kubernetes-native-applications)
- [ACM Governance Documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.11/html/governance/index)
- [Operator Lifecycle Manager Documentation](https://olm.operatorframework.io/)

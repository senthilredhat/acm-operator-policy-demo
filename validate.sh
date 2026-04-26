#!/bin/bash
# Validation script for ACM GitOps structure
# Run this script whenever you make changes to verify the structure

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "ACM GitOps Structure Validation"
echo "========================================="
echo ""

# Track failures
FAILED=0

# Function to validate kustomize build
validate_build() {
    local path=$1
    local description=$2

    echo -n "  Building $description... "
    if oc kustomize "$path" > /dev/null 2>&1; then
        echo "✓"
    else
        echo "✗ FAILED"
        FAILED=1
    fi
}

# Validate all layers
echo "Layer 1: Components"
validate_build "components/gitlab-operator" "components/gitlab-operator"
echo ""

echo "Layer 2: Cluster Configurations"
validate_build "clusters/c01/gitlab-operator" "clusters/c01/gitlab-operator"
echo ""

echo "Layer 2b: Cluster Root (CRITICAL)"
validate_build "clusters/c01" "clusters/c01 (subscription target)"
echo ""

echo "Layer 3: Cluster Subscriptions"
validate_build "app-of-app-cluster-subs/c01" "app-of-app-cluster-subs/c01"
echo ""

echo "Layer 4: Bootstrap"
validate_build "app-of-app-manifest" "app-of-app-manifest"
echo ""

# Verify subscription paths
echo "========================================="
echo "Subscription Path Verification"
echo "========================================="
echo ""

TOP_LEVEL_PATH=$(oc kustomize app-of-app-manifest/initialize-acm-gitops/ | grep "apps.open-cluster-management.io/git-path:" | head -1 | awk '{print $2}')
echo "  Top-level subscription git-path: $TOP_LEVEL_PATH"
if [ "$TOP_LEVEL_PATH" = "app-of-app-cluster-subs" ]; then
    echo "  ✓ Correct"
else
    echo "  ✗ Expected: app-of-app-cluster-subs"
    FAILED=1
fi
echo ""

CLUSTER_PATH=$(oc kustomize app-of-app-cluster-subs/c01/ | grep "apps.open-cluster-management.io/git-path:" | head -1 | awk '{print $2}')
echo "  Cluster c01 subscription git-path: $CLUSTER_PATH"
if [ "$CLUSTER_PATH" = "clusters/c01" ]; then
    echo "  ✓ Correct"
else
    echo "  ✗ Expected: clusters/c01"
    FAILED=1
fi
echo ""

# Verify Placement and PlacementBinding references
echo "========================================="
echo "Placement Reference Verification"
echo "========================================="
echo ""

PLACEMENT_NAME=$(oc kustomize clusters/c01/gitlab-operator/ | grep -A 3 "kind: Placement" | grep "name:" | head -1 | awk '{print $2}')
echo "  Placement name: $PLACEMENT_NAME"

BINDING_REF=$(oc kustomize clusters/c01/gitlab-operator/ | awk '/placementRef:/,/subjects:/' | grep "name:" | awk '{print $2}' | head -1)
echo "  PlacementBinding references: $BINDING_REF"

if [ "$PLACEMENT_NAME" = "$BINDING_REF" ]; then
    echo "  ✓ References match"
else
    echo "  ✗ Mismatch detected!"
    FAILED=1
fi
echo ""

# Final result
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo "✓ All validations passed!"
    echo "========================================="
    exit 0
else
    echo "✗ Validation failed. Please fix the errors above."
    echo "========================================="
    exit 1
fi

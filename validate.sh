#!/usr/bin/env bash
# Validation script for ACM GitOps label-based group placement structure.
# Run after any structural changes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "ACM GitOps Structure Validation"
echo "========================================="
echo ""

FAILED=0

validate_build() {
    local path=$1
    local description=$2
    echo -n "  Building $description... "
    if kubectl kustomize "$path" > /dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        kubectl kustomize "$path" 2>&1 | sed 's/^/    /'
        FAILED=1
    fi
}

# ---------------------------------------------------------------------------
echo "Components"
validate_build "components/gitlab-operator" "components/gitlab-operator"
echo ""

# ---------------------------------------------------------------------------
echo "Groups (label-based group placements)"
validate_build "groups/qa"    "groups/qa"
validate_build "groups/wave1" "groups/wave1"
validate_build "groups/wave2" "groups/wave2"
validate_build "groups/prod"  "groups/prod"
echo ""

# ---------------------------------------------------------------------------
echo "Group Subscriptions"
validate_build "app-of-app-group-subs/qa"    "app-of-app-group-subs/qa"
validate_build "app-of-app-group-subs/wave1" "app-of-app-group-subs/wave1"
validate_build "app-of-app-group-subs/wave2" "app-of-app-group-subs/wave2"
validate_build "app-of-app-group-subs/prod"  "app-of-app-group-subs/prod"
validate_build "app-of-app-group-subs"       "app-of-app-group-subs (subscription target)"
echo ""

# ---------------------------------------------------------------------------
echo "Bootstrap"
validate_build "app-of-app-manifest" "app-of-app-manifest"
echo ""

# ---------------------------------------------------------------------------
echo "========================================="
echo "Policy Name Verification"
echo "========================================="
echo ""

echo -n "  groups/qa contains policy-gitlab-operator ... "
if kubectl kustomize groups/qa 2>/dev/null | grep -q "name: policy-gitlab-operator"; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

echo -n "  groups/qa contains serverless-operator-policy ... "
if kubectl kustomize groups/qa 2>/dev/null | grep -q "name: serverless-operator-policy"; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi
echo ""

# ---------------------------------------------------------------------------
echo "========================================="
echo "Placement Name Verification"
echo "========================================="
echo ""

for group in qa wave1 wave2 prod; do
    PLACEMENT=$(kubectl kustomize "groups/$group" 2>/dev/null \
        | grep -A1 "^kind: Placement$" | grep "name:" | awk '{print $2}' | head -1)
    BINDING_REF=$(kubectl kustomize "groups/$group" 2>/dev/null \
        | awk '/placementRef:/,/subjects:/' | grep "name:" | awk '{print $2}' | head -1)
    echo -n "  groups/$group: placement=$PLACEMENT  bindingRef=$BINDING_REF  "
    if [ "$PLACEMENT" = "$BINDING_REF" ]; then
        echo "OK"
    else
        echo "MISMATCH"
        FAILED=1
    fi
done
echo ""

# ---------------------------------------------------------------------------
echo "========================================="
echo "Subscription Git-Path Verification"
echo "========================================="
echo ""

GROUP_SUB_PATH=$(grep "git-path:" app-of-app-manifest/initialize-acm-gitops/group-subscription.yaml | awk '{print $2}')
echo -n "  group-subscription git-path: $GROUP_SUB_PATH ... "
if [ "$GROUP_SUB_PATH" = "app-of-app-group-subs" ]; then
    echo "OK"
else
    echo "FAILED  (expected app-of-app-group-subs)"
    FAILED=1
fi

for group in qa wave1 wave2 prod; do
    SUB_PATH=$(grep "git-path:" "app-of-app-group-subs/$group/subscription.yaml" | awk '{print $2}')
    echo -n "  $group subscription git-path: $SUB_PATH ... "
    if [ "$SUB_PATH" = "groups/$group" ]; then
        echo "OK"
    else
        echo "FAILED - expected groups/$group"
        FAILED=1
    fi
done
echo ""

# ---------------------------------------------------------------------------
echo "========================================="
echo "Kustomization File Existence Check"
echo "========================================="
echo ""

for dir in groups/qa groups/wave1 groups/wave2 groups/prod \
           app-of-app-group-subs/qa app-of-app-group-subs/wave1  \
           app-of-app-group-subs/wave2 app-of-app-group-subs/prod \
           app-of-app-group-subs app-of-app-manifest; do
    echo -n "  $dir/kustomization.yaml ... "
    if [ -f "$dir/kustomization.yaml" ]; then
        echo "OK"
    else
        echo "MISSING"
        FAILED=1
    fi
done
echo ""

# ---------------------------------------------------------------------------
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo "All validations passed."
else
    echo "Validation FAILED. Fix the errors above."
fi
echo "========================================="
[ $FAILED -eq 0 ]

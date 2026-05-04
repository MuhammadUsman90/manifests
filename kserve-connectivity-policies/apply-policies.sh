#!/bin/bash
# Script to apply KServe connectivity policies
# Usage: ./apply-policies.sh [user-namespace]
# Example: ./apply-policies.sh kubeflow-user-example-com

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_NAMESPACE="${1:-kubeflow-user-example-com}"

echo "==========================================="
echo "KServe Connectivity Policies Installer"
echo "==========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
kubectl version --client > /dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }
kubectl cluster-info > /dev/null 2>&1 || { echo "Error: Cannot connect to cluster"; exit 1; }

# Check if Kyverno is installed
KYVERNO_INSTALLED=$(kubectl get deployment -n kyverno kyverno 2>/dev/null && echo "yes" || echo "no")

echo ""
echo "=== Step 1: Apply cluster-wide NetworkPolicy (istio-system) ==="
kubectl apply -f "${SCRIPT_DIR}/01-networkpolicy-user-to-cluster-local-gateway.yaml"
echo "✓ Applied NetworkPolicy for cluster-local-gateway"

if [ "$KYVERNO_INSTALLED" == "yes" ]; then
    echo ""
    echo "=== Step 2: Apply Kyverno ClusterPolicies (auto-generation) ==="
    kubectl apply -f "${SCRIPT_DIR}/04-kyverno-auto-generate-policies.yaml"
    echo "✓ Applied Kyverno policies - will auto-generate for all user namespaces"
    echo ""
    echo "Kyverno will automatically create the following in each user namespace:"
    echo "  - NetworkPolicy: allow-knative-serving-to-inferenceservice"
    echo "  - AuthorizationPolicy: allow-knative-serving-system"
    echo "  - AuthorizationPolicy: allow-knative-probes"
else
    echo ""
    echo "=== Step 2: Kyverno not detected - applying manual policies ==="
    echo "Target namespace: ${USER_NAMESPACE}"

    # Update namespace in files and apply
    for file in 02-networkpolicy-knative-to-inferenceservice.yaml \
                03-authorizationpolicy-knative-to-inferenceservice.yaml \
                05-networkpolicy-autoscaler-metrics.yaml \
                06-authorizationpolicy-internal-inference.yaml; do
        if [ -f "${SCRIPT_DIR}/${file}" ]; then
            echo "Applying ${file} to namespace ${USER_NAMESPACE}..."
            sed "s/namespace: kubeflow-user-example-com/namespace: ${USER_NAMESPACE}/g" \
                "${SCRIPT_DIR}/${file}" | kubectl apply -f -
        fi
    done
    echo "✓ Applied manual policies to ${USER_NAMESPACE}"
    echo ""
    echo "NOTE: Run this script for each user namespace:"
    echo "  ./apply-policies.sh <namespace-name>"
fi

echo ""
echo "=== Step 3: Verification ==="
echo ""
echo "Checking NetworkPolicies in istio-system:"
kubectl get networkpolicy -n istio-system -l app.kubernetes.io/component=kserve-networking 2>/dev/null || echo "  (none found)"

echo ""
echo "Checking NetworkPolicies in ${USER_NAMESPACE}:"
kubectl get networkpolicy -n "${USER_NAMESPACE}" 2>/dev/null | grep -E "knative|kserve" || echo "  (none found yet - Kyverno will create on namespace label)"

echo ""
echo "Checking AuthorizationPolicies in ${USER_NAMESPACE}:"
kubectl get authorizationpolicy -n "${USER_NAMESPACE}" 2>/dev/null | grep -E "knative|kserve" || echo "  (none found yet - Kyverno will create on namespace label)"

echo ""
echo "==========================================="
echo "Installation complete!"
echo "==========================================="
echo ""
echo "To test connectivity:"
echo "  kubectl run test-curl --rm -it --image=curlimages/curl -n ${USER_NAMESPACE} -- \\"
echo "    curl -v http://<inferenceservice-name>.${USER_NAMESPACE}.svc.cluster.local/v1/models/<model-name>"
echo ""

# KServe Connectivity Policies

This directory contains NetworkPolicies and AuthorizationPolicies required for KServe InferenceServices to work correctly with Kubeflow's multi-tenant setup.

## Problem Statement

After Kubeflow 1.10 (26.03), restrictive NetworkPolicies were introduced that block:
1. Internal cluster traffic to `cluster-local-gateway`
2. Knative activator/autoscaler traffic to InferenceService pods
3. Metrics scraping for autoscaling

This results in:
- External access works ✓
- Internal access fails with 503 ✗

## Policies Overview

| File | Type | Namespace | Purpose |
|------|------|-----------|---------|
| `01-networkpolicy-user-to-cluster-local-gateway.yaml` | NetworkPolicy | istio-system | Allow user namespaces → cluster-local-gateway |
| `02-networkpolicy-knative-to-inferenceservice.yaml` | NetworkPolicy | user-ns | Allow knative-serving → InferenceService pods |
| `03-authorizationpolicy-knative-to-inferenceservice.yaml` | AuthorizationPolicy | user-ns | Allow Knative system traffic via Istio |
| `04-kyverno-auto-generate-policies.yaml` | ClusterPolicy | cluster | Auto-generate policies for all user namespaces |
| `05-networkpolicy-autoscaler-metrics.yaml` | NetworkPolicy | user-ns | Allow metrics scraping for autoscaling |
| `06-authorizationpolicy-internal-inference.yaml` | AuthorizationPolicy | user-ns | Allow internal inference calls |

## Quick Start

### Option 1: With Kyverno (Recommended)

```bash
# Apply all policies - Kyverno will auto-generate for user namespaces
kustomize build . | kubectl apply -f -
```

### Option 2: Manual (Without Kyverno)

```bash
# Apply cluster-wide policy
kubectl apply -f 01-networkpolicy-user-to-cluster-local-gateway.yaml

# Apply per-namespace (change namespace in files first)
kubectl apply -f 02-networkpolicy-knative-to-inferenceservice.yaml
kubectl apply -f 03-authorizationpolicy-knative-to-inferenceservice.yaml
kubectl apply -f 05-networkpolicy-autoscaler-metrics.yaml
kubectl apply -f 06-authorizationpolicy-internal-inference.yaml
```

### Option 3: Using the Script

```bash
./apply-policies.sh kubeflow-user-example-com
```

## Traffic Flow After Applying Policies

```
Internal Request:
  User Pod (user-ns)
       │
       ▼ [01: NetworkPolicy allows]
  cluster-local-gateway (istio-system)
       │
       ▼ [existing policy]
  activator (knative-serving)
       │
       ▼ [02+03: NetworkPolicy + AuthorizationPolicy allow]
  InferenceService Pod (user-ns)
       │
       ▼
  Response
```

## Verification

```bash
# Test internal connectivity
kubectl run test-curl --rm -it --image=curlimages/curl -n <user-namespace> -- \
  curl -v http://<isvc-name>.<user-namespace>.svc.cluster.local/v1/models/<model>

# Check policies are applied
kubectl get networkpolicy -n istio-system
kubectl get networkpolicy -n <user-namespace>
kubectl get authorizationpolicy -n <user-namespace>
```

## Related Issues

- PR #3342: NetworkPolicy refactoring that introduced restrictions
- Knative Issue #11877: Activator cross-namespace connectivity
- KServe Discussion: Internal cluster access patterns

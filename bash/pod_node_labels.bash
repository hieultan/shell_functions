#!/bin/bash

# Get pods and their associated node information with labels
# Usage: pod_node_labels [KUBECTL_OPTIONS]
pod_node_labels() {
    # Get pods with their node names and pod IPs
    local pods=$(kubectl get pods "$@" -o json | jq -c '.items|map({nodeName: .spec.nodeName, podName: .metadata.name, podIP: .status.podIP})')
    # Get all nodes with their labels and names
    local nodes=$(kubectl get nodes -o json | jq -c '.items|map(.metadata.labels+{nodeName: .metadata.name})')
    # Join pods and nodes data based on nodeName
    jq -s '[.[0][] as $pod | (.[1][] | select($pod.nodeName == .nodeName) as $node | {podName: $pod.podName, podIP: $pod.podIP}+$node)]' <(echo "$pods") <(echo "$nodes")
}

# Generate a map of pod names to a specific node label
# Usage: podname_to_node_label <NODE_LABEL> [KUBECTL_OPTIONS]
podname_to_node_label() {
    local label="$1"
    if [[ -z "$label" ]]; then
        echo "Error: NODE_LABEL is required." >&2
        return 1
    fi
    shift
    # Get pod-node data and extract the specified label for each pod
    local data=$(pod_node_labels "$@" | jq -c '.[]')
    echo "$data" | jq -r --arg label "$label" '. | {(.podName): .[$label]}'
}

# Map pod names to their availability zones
# Usage: podname_to_az [KUBECTL_OPTIONS]
podname_to_az() {
    # Use the Kubernetes topology zone label to determine AZ
    podname_to_node_label topology.kubernetes.io/zone "$@"
}

# Map pod names to their node's EC2 instance types
# Usage: pod_to_instance_type [KUBECTL_OPTIONS]
pod_to_instance_type() {
    # Use the standard Kubernetes instance type label
    podname_to_node_label node.kubernetes.io/instance-type "$@"
}

# Map pod names to their Karpenter node pool names
# Usage: pod_to_karpenter_nodepool [KUBECTL_OPTIONS]
pod_to_karpenter_nodepool() {
    # Only consider nodes that are initialized by Karpenter
    local data=$(pod_node_labels "$@" | jq --arg karpenter_init "karpenter.sh/initialized" -c '.[]|select(.[$karpenter_init] == "true")')
    # Extract the Karpenter nodepool label for each pod
    echo "$data" | jq -r '. | {(.podName): .["karpenter.sh/nodepool"]}'
}

# Count pods per availability zone
# Usage: pod_per_az [KUBECTL_OPTIONS]
pod_per_az() {
    # Group pods by AZ and count them
    pod_node_labels "$@" | jq -r '. | group_by(."topology.kubernetes.io/zone") | map({az: .[0]."topology.kubernetes.io/zone", count: length})'
}

# Help function to display usage information
show_help() {
    cat << EOF
Kubernetes Pod Node Label Functions

Available Functions:
  pod_node_labels [KUBECTL_OPTIONS]
    Get pods and their associated node information with labels

  podname_to_node_label <NODE_LABEL> [KUBECTL_OPTIONS]
    Generate a map of pod names to a specific node label

  podname_to_az [KUBECTL_OPTIONS]
    Map pod names to their availability zones

  pod_to_instance_type [KUBECTL_OPTIONS]
    Map pod names to their node's EC2 instance types

  pod_to_karpenter_nodepool [KUBECTL_OPTIONS]
    Map pod names to their Karpenter node pool names

  pod_per_az [KUBECTL_OPTIONS]
    Count pods per availability zone

Examples:
  pod_node_labels --namespace default
  podname_to_az -n production
  pod_to_instance_type --all-namespaces
  pod_per_az -l app=nginx

Requirements:
  - kubectl (configured and authenticated)
  - jq (JSON processor)

EOF
}

# If script is run directly (not sourced), show help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
    else
        echo "Error: This script should be sourced or used with --help" >&2
        echo "Usage: source ${BASH_SOURCE[0]}" >&2
        exit 1
    fi
fi

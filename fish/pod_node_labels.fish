function pod_node_labels -d "Get pods and their associated node information with labels. Usage: pod_node_labels [KUBECTL_OPTIONS]"
  # Get pods with their node names and pod IPs
  set pods $(kubectl get pods $argv -o json | jq -c '.items|map({nodeName: .spec.nodeName, podName: .metadata.name, podIP: .status.podIP})')
  # Get all nodes with their labels and names
  set nodes $(kubectl get nodes -o json | jq -c '.items|map(.metadata.labels+{nodeName: .metadata.name})')
  # Join pods and nodes data based on nodeName
  jq -s '[.[0][] as $pod | (.[1][] | select($pod.nodeName == .nodeName) as $node | {podName: $pod.podName, podIP: $pod.podIP}+$node)]' (echo $pods | psub) (echo $nodes | psub)
end

function podname_to_node_label -d "Generate a map of pod names to a specific node label. Usage: podname_to_node_label <NODE_LABEL> [KUBECTL_OPTIONS]"
  set -l label $argv[1]
  if test -z "$label"
    echo "Error: NODE_LABEL is required." >&2
    return 1
  end
  set --erase argv[1]
  # Get pod-node data and extract the specified label for each pod
  set data $(pod_node_labels $argv | jq -c '.[]')
  echo $data | jq -r --arg label $label '. | {(.podName): .[$label]}'
end

function podname_to_az -d "Map pod names to their availability zones. Usage: podname_to_az [KUBECTL_OPTIONS]"
  podname_to_node_label topology.kubernetes.io/zone $argv
end

function pod_to_instance_type -d "Map pod names to their node's EC2 instance types. Usage: pod_to_instance_type [KUBECTL_OPTIONS]"
  # Use the standard Kubernetes instance type label
  podname_to_node_label node.kubernetes.io/instance-type $argv
end

function pod_to_karpenter_nodepool -d "Map pod names to their Karpenter node pool names. Usage: pod_to_karpenter_nodepool [KUBECTL_OPTIONS]"
# set fish_trace 1
  # Only consider nodes that are initialized by Karpenter
  set -a args '-l karpenter.sh/initialized=true'
  set -l data $(pod_node_labels $argv | jq --arg karpenter_init "karpenter.sh/initialized" -c '.[]|select(.[$karpenter_init] == "true")')
  # Extract the Karpenter nodepool label for each pod
  echo $data | jq -r '. | {(.podName): .["karpenter.sh/nodepool"]}'
end

function pod_per_az -d "Count pods per availability zone. Usage: pod_per_az [KUBECTL_OPTIONS]"
  # Group pods by AZ and count them
  pod_node_labels $argv  | jq -r '. | group_by(."topology.kubernetes.io/zone") | map({az: .[0]."topology.kubernetes.io/zone", count: length})'
end

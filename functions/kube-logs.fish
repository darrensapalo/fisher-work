# This gets the list of names of pods in a kubernetes cluster, and then runs them through fuzzy finder.
# The logs are then displayed for whichever pod you select.
function kube-logs
  set -l handler (kubectl get pods --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | fzf )
  kubectl logs -f $handler
end
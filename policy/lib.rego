# Shared helpers for the homelab policies. Input: every rendered manifest,
# combined (conftest test --combine). Data: the approved register entries
# (scripts/security/registers.py data).
package lib

import rego.v1

# Every Kubernetes object in the combined input that the reconciler applies.
# Helm test hooks are rendered by kustomize but never deployed.
objects contains o if {
	some o in raw
	not helm_test(o)
}

raw contains o if {
	some f in input
	is_array(f.contents)
	some o in f.contents
	is_object(o)
	o.kind
}

raw contains o if {
	some f in input
	is_object(f.contents)
	o := f.contents
	o.kind
}

helm_test(o) if contains(object.get(object.get(o.metadata, "annotations", {}), "helm.sh/hook", ""), "test")

ref(o) := sprintf("%s/%s", [object.get(o.metadata, "namespace", "_cluster"), o.metadata.name])

# Approved entries of one register. Unapproved entries never reach data.
approved(register) := entries if {
	entries := data.registers[register]
} else := []

# Pod templates in every workload kind.
pod_spec(o) := o.spec if o.kind == "Pod"

pod_spec(o) := o.spec.template.spec if o.kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

pod_spec(o) := o.spec.jobTemplate.spec.template.spec if o.kind == "CronJob"

containers(spec) := array.concat(
	object.get(spec, "containers", []),
	array.concat(object.get(spec, "initContainers", []), object.get(spec, "ephemeralContainers", [])),
)

workloads contains o if {
	some o in objects
	pod_spec(o)
}

namespaces contains n if {
	some o in objects
	o.kind == "Namespace"
	n := o.metadata.name
}

# The permissions register: does an approved entry cover this subject and grant?
permitted(subject, grant) if {
	some e in approved("permissions")
	e.subject == subject
	grant in e.grants
}

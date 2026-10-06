# Permissions (policy §9.1; HS-PERM-01..05). Each [subject, grant] below
# needs an approved entry in security/registers/permissions.yaml.
package permissions

import data.lib
import rego.v1

subject(o) := sprintf("%s/%s", [o.kind, lib.ref(o)])

read_verbs := {"get", "list", "watch", "*"}

roles contains o if {
	some o in lib.objects
	o.kind in {"Role", "ClusterRole"}
}

# HS-PERM-01: a binding to cluster-admin.
findings contains [subject(o), "cluster-admin"] if {
	some o in lib.objects
	o.kind in {"RoleBinding", "ClusterRoleBinding"}
	o.roleRef.name == "cluster-admin"
}

# HS-PERM-02: a wildcard verb or resource.
findings contains [subject(o), "wildcard"] if {
	some o in roles
	some r in object.get(o, "rules", [])
	some x in array.concat(object.get(r, "verbs", []), object.get(r, "resources", []))
	x == "*"
}

# HS-PERM-03: read access to Secrets.
findings contains [subject(o), "secrets-read"] if {
	some o in roles
	some r in object.get(o, "rules", [])
	some res in object.get(r, "resources", [])
	res in {"secrets", "*"}
	some v in object.get(r, "verbs", [])
	v in read_verbs
}

# HS-PERM-04: host access or privilege in a pod.
findings contains [subject(o), "privileged"] if {
	some o in lib.workloads
	some c in lib.containers(lib.pod_spec(o))
	c.securityContext.privileged == true
}

findings contains [subject(o), g] if {
	some o in lib.workloads
	spec := lib.pod_spec(o)
	some g in {"hostNetwork", "hostPID", "hostIPC"}
	spec[g] == true
}

findings contains [subject(o), "hostPath"] if {
	some o in lib.workloads
	some v in object.get(lib.pod_spec(o), "volumes", [])
	v.hostPath
}

findings contains [subject(o), g] if {
	some o in lib.workloads
	some c in lib.containers(lib.pod_spec(o))
	some cap in object.get(object.get(object.get(c, "securityContext", {}), "capabilities", {}), "add", [])
	cap != "NET_BIND_SERVICE"
	g := sprintf("capability:%s", [cap])
}

# HS-PERM-05: a namespace that lets privileged pods run.
findings contains [subject(o), "pss-privileged"] if {
	some o in lib.objects
	o.kind == "Namespace"
	object.get(object.get(o.metadata, "labels", {}), "pod-security.kubernetes.io/enforce", "") == "privileged"
}

deny contains msg if {
	some [s, g] in findings
	not lib.permitted(s, g)
	msg := sprintf("HS-PERM %s: grant %q has no approved entry in security/registers/permissions.yaml (policy §9.1)", [s, g])
}

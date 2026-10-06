# Unit tests: conftest verify --policy policy
package policy_test

import data.data_handling
import data.permissions
import data.publish
import data.rotation
import rego.v1

fa := "kube-system-authentik-forward-auth@kubernetescrd"

edge := "kube-system-crowdsec@kubernetescrd,kube-system-rate-limit@kubernetescrd"

ingress(ns, name, host, path, mws) := {
	"kind": "Ingress",
	"metadata": {"namespace": ns, "name": name, "annotations": {"traefik.ingress.kubernetes.io/router.middlewares": mws}},
	"spec": {"tls": [{"hosts": [host]}], "rules": [{"host": host, "http": {"paths": [{"path": path}]}}]},
}

forward_auth_mw := {
	"kind": "Middleware",
	"metadata": {"namespace": "kube-system", "name": "authentik-forward-auth"},
	"spec": {"forwardAuth": {"authResponseHeaders": ["X-authentik-username", "X-authentik-jwt"]}},
}

wrap(objs) := [{"path": "t.yaml", "contents": objs}]

net06(denies) := {m | some m in denies; startswith(m, "HS-NET-06")}

test_unauthenticated_route_without_entry_is_denied if {
	d := publish.deny with input as wrap([ingress("a", "a", "a.example", "/", edge)])
	count(net06(d)) == 1
}

test_forward_auth_route_passes if {
	d := publish.deny with input as wrap([ingress("a", "a", "a.example", "/", concat(",", [edge, fa]))])
	count(net06(d)) == 0
}

test_approved_entry_covering_all_routes_passes if {
	d := publish.deny with input as wrap([ingress("a", "a", "a.example", "/", edge)])
		with data.registers.publication as [{"ingress": "a/a", "routes": ["a.example/"]}]
	count(net06(d)) == 0
}

test_entry_missing_a_route_is_denied if {
	d := publish.deny with input as wrap([ingress("a", "a", "a.example", "/new", edge)])
		with data.registers.publication as [{"ingress": "a/a", "routes": ["a.example/"]}]
	count(net06(d)) == 1
}

test_outpost_callback_is_exempt if {
	d := publish.deny with input as wrap([ingress("a", "o", "a.example", "/outpost.goauthentik.io", edge)])
	count(net06(d)) == 0
}

test_missing_edge_middleware_is_denied if {
	d := publish.deny with input as wrap([ingress("a", "a", "a.example", "/", fa)])
	count({m | some m in d; startswith(m, "HS-NET-05")}) == 2
}

test_carve_out_must_blank_every_forwarded_header if {
	partial := {
		"kind": "Middleware",
		"metadata": {"namespace": "a", "name": "strip"},
		"spec": {"headers": {"customRequestHeaders": {"X-authentik-username": ""}}},
	}
	objs := [
		forward_auth_mw, partial,
		ingress("a", "main", "a.example", "/", concat(",", [edge, fa])),
		ingress("a", "api", "a.example", "/api", concat(",", [edge, "a-strip@kubernetescrd"])),
	]
	d := publish.deny with input as wrap(objs)
		with data.registers.publication as [{"ingress": "a/api", "routes": ["a.example/api"]}]
	some m in d
	startswith(m, "HS-NET-07 a/api")
	contains(m, "X-authentik-jwt")
}

binding := {
	"kind": "ClusterRoleBinding",
	"metadata": {"name": "b"},
	"roleRef": {"name": "cluster-admin"},
}

test_cluster_admin_binding_needs_an_entry if {
	d := permissions.deny with input as wrap([binding])
	count(d) == 1
}

test_cluster_admin_binding_with_approved_entry_passes if {
	d := permissions.deny with input as wrap([binding])
		with data.registers.permissions as [{"subject": "ClusterRoleBinding/_cluster/b", "grants": ["cluster-admin"]}]
	count(d) == 0
}

test_c4_volume_on_unencrypted_store_is_denied if {
	ns := {"kind": "Namespace", "metadata": {"name": "v", "labels": {"homelab/data-class": "c4", "homelab/criticality": "tier-1"}}}
	pvc := {"kind": "PersistentVolumeClaim", "metadata": {"namespace": "v", "name": "data"}, "spec": {"storageClassName": "local-path"}}
	d := data_handling.deny with input as wrap([ns, pvc])
		with data.registers["data-stores"] as [{"id": "D-04", "storage_classes": ["local-path"], "at_rest": "unverified"}]
	some m in d
	startswith(m, "HS-REST-02 PVC v/data")
}

ds(ns, name) := {
	"kind": "DopplerSecret",
	"metadata": {"name": name},
	"spec": {"managedSecret": {"namespace": ns, "name": name}},
}

dep(ns, name, sname, ann) := {
	"kind": "Deployment",
	"metadata": {"namespace": ns, "name": name, "annotations": ann},
	"spec": {"template": {"spec": {"containers": [{"name": "c", "image": "x", "envFrom": [{"secretRef": {"name": sname}}]}]}}},
}

test_unregistered_doppler_secret_is_denied if {
	d := rotation.deny with input as wrap([ds("a", "s")]) with data.registers.secrets as []
	count(d) == 1
}

test_registered_doppler_secret_passes if {
	d := rotation.deny with input as wrap([ds("a", "s")]) with data.registers.secrets as [{"secret": "a/s", "reload": "manual"}]
	count(d) == 0
}

test_auto_reload_needs_the_annotation if {
	d := rotation.deny with input as wrap([ds("a", "s"), dep("a", "app", "s", {})])
		with data.registers.secrets as [{"secret": "a/s", "reload": "auto"}]
	count(d) == 1
}

test_annotated_deployment_passes if {
	d := rotation.deny with input as wrap([ds("a", "s"), dep("a", "app", "s", {"secrets.doppler.com/reload": "true"})])
		with data.registers.secrets as [{"secret": "a/s", "reload": "auto"}]
	count(d) == 0
}

test_unknown_storage_class_is_denied if {
	pvc := {"kind": "PersistentVolumeClaim", "metadata": {"namespace": "v", "name": "data"}, "spec": {"storageClassName": "mystery"}}
	d := data_handling.deny with input as wrap([pvc])
		with data.registers["data-stores"] as []
	some m in d
	startswith(m, "HS-REST-01")
}

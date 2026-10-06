# Publishing a route (policy §9.7; HS-NET-05, HS-NET-06, HS-NET-07).
package publish

import data.lib
import rego.v1

forward_auth := "kube-system-authentik-forward-auth@kubernetescrd"

outpost_prefix := "/outpost.goauthentik.io"

ingresses contains o if {
	some o in lib.objects
	o.kind == "Ingress"
}

middlewares(o) := {trim_space(m) |
	some m in split(object.get(object.get(o.metadata, "annotations", {}), "traefik.ingress.kubernetes.io/router.middlewares", ""), ",")
	m != ""
}

routes(o) := {sprintf("%s%s", [r.host, object.get(p, "path", "/")]) |
	some r in o.spec.rules
	some p in r.http.paths
}

hosts(o) := {r.host | some r in o.spec.rules}

authenticated(o) if forward_auth in middlewares(o)

# Only the identity provider's own callback paths.
outpost_only(o) if {
	every r in routes(o) {
		contains(r, outpost_prefix)
	}
}

# HS-NET-05: TLS, rate limit and intrusion detection on every route.
deny contains msg if {
	some o in ingresses
	some m in {"kube-system-crowdsec@kubernetescrd", "kube-system-rate-limit@kubernetescrd"}
	not m in middlewares(o)
	msg := sprintf("HS-NET-05 %s: published without middleware %s", [lib.ref(o), m])
}

deny contains msg if {
	some o in ingresses
	some h in hosts(o)
	tls_hosts := {t | some x in object.get(o.spec, "tls", []); some t in object.get(x, "hosts", [])}
	not h in tls_hosts
	msg := sprintf("HS-NET-05 %s: host %s has no TLS", [lib.ref(o), h])
}

# HS-NET-06: identity-provider authentication, or an approved register entry
# that lists every route of this Ingress.
registered(o) if {
	some e in lib.approved("publication")
	e.ingress == lib.ref(o)
	every r in routes(o) {
		r in {x | some x in e.routes}
	}
}

deny contains msg if {
	some o in ingresses
	not authenticated(o)
	not outpost_only(o)
	not registered(o)
	msg := sprintf(
		"HS-NET-06 %s: routes %v are published without the identity provider and have no approved entry in security/registers/publication.yaml (policy §9.7). An agent: add a proposed entry and ask the owner; do not approve it.",
		[lib.ref(o), sort(routes(o))],
	)
}

# HS-NET-07: a carve-out on a host that also uses forward auth must blank
# every identity header that forward auth passes to applications.
forward_auth_headers := {h |
	some m in lib.objects
	m.kind == "Middleware"
	m.metadata.name == "authentik-forward-auth"
	some h in m.spec.forwardAuth.authResponseHeaders
}

blanked(o) := {h |
	some ref in middlewares(o)
	endswith(ref, "@kubernetescrd")
	some m in lib.objects
	m.kind == "Middleware"
	ref == sprintf("%s-%s@kubernetescrd", [m.metadata.namespace, m.metadata.name])
	some h, v in object.get(object.get(m.spec, "headers", {}), "customRequestHeaders", {})
	v == ""
}

deny contains msg if {
	some o in ingresses
	not authenticated(o)
	not outpost_only(o)
	some other in ingresses
	authenticated(other)
	count(hosts(o) & hosts(other)) > 0
	missing := forward_auth_headers - blanked(o)
	count(missing) > 0
	msg := sprintf(
		"HS-NET-07 %s: shares a host with forward-auth routes but does not blank the identity headers %v",
		[lib.ref(o), sort(missing)],
	)
}

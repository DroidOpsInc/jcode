# OPA / Conftest policy for jcode release bundles.
#
# Evaluated by the `policy:release` job in .gitlab-ci.yml against
# dist/release-bundle.json before a tag is promoted to a GitLab Release.
#
# The bundle MUST:
#   - Carry exactly the four supported (os, arch) pairs.
#   - Carry both a CycloneDX and an SPDX SBOM.
#   - Use the canonical jcode-{os}-{arch} asset name shape (DROIDOPS.md
#     install instructions and scripts/install.sh depend on this).

package release

# --- supported targets ---

required_targets := {
    {"os": "linux",   "arch": "x86_64"},
    {"os": "linux",   "arch": "aarch64"},
    {"os": "macos",   "arch": "aarch64"},
    {"os": "windows", "arch": "x86_64"},
}

binary_targets[t] {
    a := input.artifacts[_]
    a.kind == "binary"
    t := {"os": a.os, "arch": a.arch}
}

deny[msg] {
    missing := required_targets - binary_targets
    count(missing) > 0
    msg := sprintf("release bundle is missing required (os, arch) targets: %v", [missing])
}

# --- SBOM coverage ---

sbom_formats[fmt] {
    a := input.artifacts[_]
    a.kind == "sbom"
    fmt := a.format
}

deny[msg] {
    not sbom_formats["cyclonedx"]
    msg := "release bundle is missing a CycloneDX SBOM"
}

deny[msg] {
    not sbom_formats["spdx"]
    msg := "release bundle is missing an SPDX SBOM"
}

# --- canonical asset naming ---

deny[msg] {
    a := input.artifacts[_]
    a.kind == "binary"
    a.os != "windows"
    not endswith(a.name, ".tar.gz")
    msg := sprintf("non-windows binary %q must use .tar.gz", [a.name])
}

deny[msg] {
    a := input.artifacts[_]
    a.kind == "binary"
    a.os == "windows"
    not endswith(a.name, ".zip")
    msg := sprintf("windows binary %q must use .zip", [a.name])
}

deny[msg] {
    a := input.artifacts[_]
    a.kind == "binary"
    expected := sprintf("jcode-%s-%s", [a.os, a.arch])
    not startswith(a.name, expected)
    msg := sprintf("binary %q does not follow jcode-{os}-{arch} naming", [a.name])
}

# --- tag must be set ---

deny[msg] {
    not input.tag
    msg := "release bundle is missing a tag"
}

deny[msg] {
    input.tag == ""
    msg := "release bundle tag is empty"
}

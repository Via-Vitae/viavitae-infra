# TFLint configuration — viavitae-infra
#
# This file is a required companion of the `tflint` job in .github/workflows/ci.yml.
# Without it TFLint evaluates no rules at all and still exits 0, which is the failure
# mode worth avoiding above all others in a lint gate: it reports clean because it
# checked nothing. The CI job asserts this file exists before running.
#
# TFLint does not replace `terraform validate`. Validate proves the configuration is
# internally consistent; TFLint proves it is idiomatic and that the things a provider
# accepts but nobody means are not present. Both run.

config {
  # compact: one line per finding, which is what a CI log is read as.
  format = "compact"

  # Inspect called modules, not only the root. Most of the real Terraform in this
  # repository lives in terraform/modules/, and a root-only lint would skip all of it.
  # `all` covers local paths now and registry modules if one is ever added; the older
  # `module = true` attribute was removed in TFLint v0.54.
  call_module_type = "all"

  # --force on the command line makes warnings fail the build. Set here as well so a
  # local `tflint` run and CI disagree about nothing.
  force = true

  # Rules are enabled by the ruleset's own defaults; `disabled_by_default` is left
  # false so a new rule added by a ruleset upgrade takes effect immediately and shows
  # up as a finding rather than arriving silently unenforced.

  # A variable with no default is required input. Calling modules must pass it, which
  # is the point: silent defaults for things like a VMID or a VLAN are how two
  # environments end up colliding.
  varfile = []
}

plugin "terraform" {
  enabled = true
  version = "0.15.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# --- Rules enabled beyond the preset -----------------------------------------

rule "terraform_comment_syntax" {
  # `//` and `/* */` are legal HCL but `#` is the convention across this repository.
  # Mixed comment syntax in one file is how a commented-out block gets uncommented
  # by accident.
  enabled = true
}

rule "terraform_documented_outputs" {
  # Every output in a module is a contract with its callers. An undocumented output
  # gets removed or retyped without anyone noticing until a plan breaks.
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true

  format {
    format = "snake_case"
  }
}

rule "terraform_typed_variables" {
  # An untyped variable is a string until something forces it to be otherwise, which
  # means a list of VLAN tags passed as "20,30" validates and then fails at apply.
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_unused_declarations" {
  # An unused variable or output in a module is a promise nobody keeps. It also hides
  # a mistake: a variable declared and never referenced usually means the author
  # intended to wire it up and did not.
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_lookup" {
  enabled = true
}

rule "terraform_empty_list_equality" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  # A module source with no version constraint resolves to whatever the registry
  # serves at init time. Every module reference in this repository is a local path,
  # which is inherently pinned; the rule stays on so a future registry module cannot
  # arrive unpinned.
  enabled = true

  style     = "semver"
  default_branches = ["main"]
}

rule "terraform_standard_module_structure" {
  # main.tf, variables.tf, outputs.tf in every module. The repository follows it, so
  # the rule documents the expectation mechanically rather than in prose.
  enabled = true
}

rule "terraform_workspace_environments" {
  # Terraform workspaces are explicitly not used: each environment is a directory with
  # its own state key. Workspaces hide which state a plan touches, and in a repository
  # that provisions production VMs that ambiguity is a hazard.
  enabled = true
}

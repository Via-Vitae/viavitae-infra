# host_vars for `dev`

One file per host, named exactly as the host appears in `../hosts.yml`, with a `.yml`
extension. Empty by default, and that is the intended state.

A variable belongs here only when it is genuinely per-host and cannot be derived:
a disk device name that differs because of controller order, an interface name that
differs because of a firmware version, a maintenance window that differs because one
host carries a database.

A variable that is per-host because someone set it that way during an incident belongs
in the group and in a comment, not here. `host_vars` is where an estate accumulates
exceptions that nobody dares remove, and an exception that is not written down as one
becomes the behaviour a new host is compared against.

Nothing in this directory may be encrypted. A per-host secret goes in
`group_vars/vault.sops.yml` under a per-host key, because a `.sops.yml` file in
`host_vars` is decrypted by the same plugin but reviewed by nobody — there is no
pull-request pattern that draws attention to it.

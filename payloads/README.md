# payloads

Files copied verbatim into the build, either over a file in the source tree or
over something on the build host. They are not patches: there is no meaningful
diff to take, because nothing of the original survives.

Everything `patch(1)` applies lives in [`../patches`](../patches) instead, one
flat directory per patch set with a `series` file selecting which versions each
diff applies to.

| Payload | Used by | What it does |
| --- | --- | --- |
| `ksh/getconf-wrapper.sh` | `shvr_install_getconf_wrapper` | Replaces `/usr/bin/getconf` **on the build host** for the duration of the ksh build, so libast's `iffe` probes read pinned values instead of whatever the host reports. Restored afterwards. |
| `ksh/dylink-noop.sh` | `shvr_build_ksh` | Overwrites `src/cmd/INIT/dylink.sh`. We only ever build static binaries, so the dynamic-linking probe is dead weight; its content differs across the ksh trees, so a diff would be a full-file replacement per version. |

A payload referenced from a variant by a literal `${SHVR_DIR_SELF}/...` path is
folded into that target's build identity, so editing one forces a rebuild. Keep
the literal path in the variant — building it up from a variable would hide the
payload from `shvr_recipe_files`.

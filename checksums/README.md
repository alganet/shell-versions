## Checksums and Verification

The `checksums/sources` directory contains `.sha256sums` files for each
downloaded artifact. The build process verifies downloads against these
checksums and will fail fast if checksums are missing or do not match.

To generate checksum files for the sources, use:

```sh
$ sh shvr.sh download $(sh shvr.sh targets)
$ sh shvr.sh generate_checksums
```

Checksums are used automatically by our `shvr_fetch` helper by default. To
disable verification set `SHVR_SKIP_VERIFY_SHA256=1` (not recommended unless
you need a temporary bypass).

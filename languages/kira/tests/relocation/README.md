# Workspace cache probes

Compile the probe from languages/kira/tests (Build resolves by name from Foundation):

```sh
kira build relocation --emit bin -o /tmp/build-relocation-probe
python3 relocation/verify.py /tmp/build-relocation-probe
python3 relocation/verify_compiler.py /tmp/build-relocation-probe
```

Both probes use temporary source workspaces and an isolated artifact store.
The second workspace is reached through a symlink, checking canonical depfile
paths as well as ordinary relocation.

`verify.py` checks action reuse, dependency-only rebuilding, independent
variants of discovered sibling inputs, snapshot-only capture, shared views,
and import after the originating workspaces are removed and collection is
forced. Collection must remove the unused dependency variant while retaining
the pinned one.

`verify_compiler.py` builds a real Kira shared library, a program importing its
sources through a path dependency, and an unrelated program. The second
workspace must compile nothing. After a library edit, only the library and
consumer may compile, and running the consumer must print the changed value.
The original workspace must remain a cache hit.

# Kira ecosystem audit — 2026-11-06

This is a **sampled compiler/build audit**, not an M7 parity claim. The host
was macOS with Xcode 27 and installed `kira 26.11.1`. Tessera system packages
were checked for their own `aarch64-unknown-tessera` target. Native macOS
executables were linked, but the graphical applications were not launched.

## Verified after fixes

| Component | Verification | Result |
| --- | --- | --- |
| Ember, KiraUI, KiraDB, ArgumentParser, KiraLayout | host `kira check` | pass |
| KCoreUI, KCoreAnimation, KiraCode, RenderBox | host `kira check` | pass |
| KiraIPC | host check; native `--emit lib`; `kira test` | pass; 14/14 tests |
| Kira Editor | host check; native executable build | pass |
| Kira Live | host check; native executable build | pass |
| TesseraUI, About, PlatformUI | Tessera-target check | pass |
| Adaptive Desktop, Adaptive Mobile, Desktop | Tessera-target check | pass |
| Tessera Browser, About UI Tests | Tessera-target check | pass |
| Project Matter Viewer, AgentServer, EditorNext, HUD | host `kira check`; native `--emit bin` | pass; all four built |
| Project Matter Viewer, HUD, EditorNext | two-frame offscreen smoke | pass; HUD/EditorNext launched from package directories |
| Project Matter AgentServer | native MCP initialize and `tools/list` | pass; clean exit |

Native builds of Kira Editor and Kira Live require
`KLF_USE_SYSTEM_LINKER=1` with this host SDK: bundled `ld64.lld` cannot parse
the new TAPI target spellings in the Xcode 27 `.tbd` files. The framework
already exposes this setting, so no linker change was necessary. The native
executables are **link successes, not GUI/runtime successes**.

## Fixed blockers

- **Native unsafe boundaries (3410):** KiraIPC, FileSystem's OS chooser,
  Kira Live's device adapter, and Tessera Browser's WebKit/GLib adapter now
  make their foreign calls in explicit unsafe scopes. This is *existing*
  language support, not a missing compiler feature.
- **Manifest paths:** moved Kira and UI package references are now pointed at
  real monorepo package roots, including 67 references in Project Matter.
  The initial audit found 377 readable paths and 88 unresolved across 243
  manifests. After repairs and addition of focused regression fixtures, the
  current inventory is **486 readable dependency paths** and **two unresolved**
  across 246 manifests. These counts check paths, not compiler-accepted
  manifests or dependency version compatibility.
- **Direct imports:** Desktop and Tessera Browser now declare the package
  dependencies for the modules they import. Project Matter's HUD now declares
  Core and Ember directly.
- **Name-resolution defect (3027):** a bare global previously selected the
  first matching declaration across all modules before checking visibility.
  `semantics/expressions.kcore` now prioritizes the declaring module and
  visible imports. A duplicate-name regression in `packages/scope-nearest`
  runs and exits **65** as expected, and Adaptive Desktop's Tessera-target
  check passes. The existing `packages/not-imported` negative case still
  reports 3027. The patched compiler is built locally, **not installed**.
- **Browser state:** replaced the stale `engine.failed` field with the
  current `startFailure` optional-state test.
- **KiraIPC test reliability:** a test now checks KIP/1's exact bytes and
  captures consuming reader calls before `expect!`. The framework's assertion
  diagnostic expansion may re-evaluate operands after a failed comparison;
  assertion expressions should not consume protocol state. All 14 tests pass.
- **Project Matter cross-package public APIs (3050):** Core, MathX, Telemetry,
  Governor, Cook, World and Agent used shared types without marking their
  declarations `public`. Exposed their intended cross-package types, including
  `Cost`, `Handle`, `Category`, `Meshlet`, `FrameProfiler`, `Governor`,
  `JobDesc`, `World`, `AuthoringScene`, `CookedMeshSet` and `AgentSession`.
  This was expected language visibility, **not a new compiler lookup defect**.
  Kept private implementation types such as Core's `HandleSlot` hidden.
  The focused positive/negative regression in
  `apps/project-matter/tests/visibility/check.sh` verifies both properties.
- **Project Matter native boundary (3410):** AgentServer's Metal screenshot
  function now wraps its autorelease-pool lifetime in an explicit `unsafe`
  scope. The API and pool lifetime are unchanged.

## Remaining observed failures

- **Project Matter target coverage:** `viewer`, `agentserver`, `editornext`
  and `hud` now all pass the installed `kira check` and native macOS builds.
  Two-frame offscreen runs of Viewer/HUD/EditorNext exit 0, and AgentServer's
  MCP initialization and tool listing return correctly. HUD and EditorNext
  must be launched from their package directories for their UI resources;
  launching their standalone binaries from the monorepo root traps on missing
  `.kcui` resources. The Tessera SDK was not installed on this host, so this
  does not establish Tessera builds or full GUI behavior.
- **UI Icon Composer:** missing readable manifests for `KiraUIFoundation`
  (`../ui-foundation`) and `OpacityUI` (`../opacity-ui`), plus an earlier source
  parse error 2002 at `app/ComposerState.kira:13` for `ComposerStore`.
- **Recovery Preview:** host check fails 3061 on `RecoveryView`, which is
  declared in the parent Recovery app rather than a declared library
  dependency. The correct shared view/package boundary is not established.
- **TesseraUI test package:** `kira check tessera-packages/tessera-ui/tests`
  reports 4010 because it has `tests/` sources but no `app/` sources. The
  normal TesseraUI package checks successfully.
- **Broader coverage:** the full set of 246 manifests has *not* been built;
  a readable path is not proof of a passing source check. Cross-target
  linking, native functionality, runtime behavior and `tests-kik` parity remain
  unverified in this audit.

## Reproduce focused compiler checks

From the monorepo root, with `klf` and `kira` on `PATH`:

```sh
KLF_USE_SYSTEM_LINKER=1 klf build languages/klf-kira/languages/kira -o /tmp/kira-audit-frontend
/tmp/kira-audit-frontend check languages/klf-kira/languages/kira/corpus/packages/scope-nearest
KLF_USE_SYSTEM_LINKER=1 /tmp/kira-audit-frontend run languages/klf-kira/languages/kira/corpus/packages/scope-nearest  # exit 65
/tmp/kira-audit-frontend check tessera-packages/adaptive-desktop --target aarch64-unknown-tessera
/tmp/kira-audit-frontend check tessera-packages/tessera-browser --target aarch64-unknown-tessera
KLF_USE_SYSTEM_LINKER=1 kira build apps/kira-live --emit bin -o /tmp/kira-live-audit
KLF_USE_SYSTEM_LINKER=1 kira build apps/kira-editor --emit bin -o /tmp/kira-editor-audit
KLF_USE_SYSTEM_LINKER=1 kira test kira-packages/kira-ipc
sh apps/project-matter/tests/visibility/check.sh
for app in viewer agentserver editornext hud; do kira check "apps/project-matter/apps/$app"; done
for app in viewer agentserver editornext hud; do
  KLF_USE_SYSTEM_LINKER=1 kira build "apps/project-matter/apps/$app" --emit bin -o "/tmp/matter-$app-audit"
done
```

This report records observed checks and their limits; it should be updated
when a remaining blocker is actually reproduced and resolved.
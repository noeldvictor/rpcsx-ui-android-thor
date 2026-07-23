# Thor exact-APK SPU continuity gate

## 2026-07-23 - stale seed diagnosis and host successor

- Status: retained
- Scope: Thor cool-title startup safety and avoidable SPU LLVM work
- Installed evidence: exact installed APK
  `490418F9A43B287C376CB9D121C5C3BC93E1AFDEA51ED618BA6AB5882D95BF63`
  loaded only `6/7` required native SPU objects in guarded title capture
  `20260723-164343-thor-input-custom`, then stopped at the first readiness
  poll at `67.0 C` before title. PID cleanup and failure resets were safe.
- Seed mismatch: the seven-object continuity floor came from stopped-prewarm
  capture `20260723-020444-firmware-ppu-prewarm`, whose expected/host and
  installed APK were instead
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`.
  The title gate checked only the current pinned candidate identity plus the
  numeric floor; it did not bind that floor to the APK that created it.
- Root cause: SPU native objects use an exact key over transformed/final LLVM
  IR and backend target identity. A seed from a different core may leave a
  stable guest-program filename prefix while its exact object key is stale.
  Treating that seed as current continuity can therefore schedule an avoidable
  cold LLVM miss during the already concurrent title startup phase.
- Rejected experiment: a bounded stable-prefix hit-first preload ordering was
  implemented and passed ARM64 native compilation, but was removed before
  commit. Prefix priority cannot prove the final-IR object key and therefore
  cannot repair an exact-key mismatch; retaining it would add work without an
  evidence-backed speed or thermal benefit.
- Retained change: `Get-ThorSpuNativeObjectReuseFloorForApk` accepts a floor
  only when both `Expected/host APK SHA-256` and `Installed APK SHA-256` in the
  stopped-prewarm README equal the current pinned APK. Status now publishes
  `spu_continuity_apk_sha256`, and the cool-title route requires that exact
  identity before serial resolution or any ADB/device contact.
- Counterproof: device-free Status for current host candidate reports
  `spu_continuity_capture=none`, `spu_continuity_apk_sha256=none`, and
  `minimum_required_spu_native_objects=0`. A direct `AndroidRouteScene` call
  with serial `must-not-be-resolved` refuses locally with the required
  stopped-prewarm message, proving the stale `5044976A...D83E5C` seed cannot
  launch the current route.
- Exact host successor artifact:
  - APK: `D6798739F7BC06E8CFDBEEFFD9AFA0369F361CA90A625E98BEA7C1E8908D549F`,
    `72,838,264` bytes;
  - merged core: `E9DDCDA308B20610F971032F24477D4638FBF034E5742C3746B99F80096F215C`,
    `1,304,307,080` bytes;
  - packaged core: `BDBA436102FD666D38D796880C824BB65873668098BED7380D0D661D934A39EE`,
    `62,988,824` bytes.
- Verification: PowerShell AST parsing, exact/mismatched/tampered hash fixtures,
  focused cache-route and cool-title profile contracts, all `69/69`
  `tools/test_thor_*.ps1` contracts, optimized ARM64-only `assembleThortest`,
  exact APK/core/ZIP identity, and `git diff --check` pass.
- Device result: no ADB query, install, launch, temperature query, or other
  Thor contact occurred in this host implementation round. The successor is
  host-only and receives no speed, title, thermal, FPS, flicker, gameplay, or
  stability credit.
- Next: one strict no-launch install may place the exact successor on Thor.
  After its independent cooldown, run one stopped prewarm for that same APK.
  Only a later independently cool title proof may consume the resulting exact
  continuity floor.

## 2026-07-23 - exact successor no-launch install

- Status: installed exact, no launch
- Strict gate: `20260723-174922-thor-input-strict-cool-gate` passed
  `30.9 -> 30.9 -> 30.5 C` (maximum `30.9 C`, rise `-0.4 C`) with battery
  `23.0 C`, skin `30.0 C`, `BootGame=False`, and `ForceStop=True`.
- Install capture: `20260723-174947-spu-continuity-exact-apk-install` proves
  host/on-device APK SHA-256
  `D6798739F7BC06E8CFDBEEFFD9AFA0369F361CA90A625E98BEA7C1E8908D549F`
  matched exactly. RPCSX PID was absent before and after; emulator launch was
  `no`; failure was `none`.
- Post-install thermal snapshot: battery `23.0 C`, skin `30.0 C`, silicon
  `32.9 C`.
- Device-free Status now selects the install as the cooldown source, keeps
  SPU continuity `none` / floor `0`, and blocks further contact until
  `2026-07-23T18:19:54.8683910-04:00`.
- Decision: retain installation identity/safety evidence only. Do not grant
  speed, title, thermal-runtime, FPS, flicker, gameplay, or stability credit.
  Do not run stopped prewarm or title in this install round.

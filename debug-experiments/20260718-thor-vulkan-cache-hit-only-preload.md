# Thor Vulkan Cache-hit-only Startup Preload

- Date: 2026-07-18
- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `host-only gated startup-thermal candidate`
- Device status: stopped; no query, install, launch, or runtime action

## Question

Can a validated warm Vulkan driver cache avoid recompiling missing RSX graphics
pipelines during startup preload, reducing avoidable CPU load and heat without
changing the ordinary runtime compilation path or risking missing graphics?

The narrow answer is yes at the API level: Vulkan pipeline cache control can
request cache-hit-only creation. A miss returns `VK_PIPELINE_COMPILE_REQUIRED`
and no pipeline instead of synchronously compiling it. The emulator can then
discard only that preload placeholder and let the unchanged runtime path
compile the pipeline when the game actually requests it.

This is not a Thor speed or temperature result. It is a default-off mechanism
with host build and contract proof only.

## Primary Research

Khronos specifies the required behavior:

- `VK_EXT_pipeline_creation_cache_control` adds
  `VkPhysicalDevicePipelineCreationCacheControlFeatures` and
  `VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT`:
  <https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_pipeline_creation_cache_control.html>
- `pipelineCreationCacheControl` must be queried and enabled before the flag is
  legal:
  <https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDevicePipelineCreationCacheControlFeatures.html>
- A cache miss with the fail-on-compile flag returns the success code
  `VK_PIPELINE_COMPILE_REQUIRED` and a null pipeline without compiling; the
  facility is core in Vulkan 1.3:
  <https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html>

Current official RPCS3 `origin/master` at `a7d90852d` does not use
`FAIL_ON_PIPELINE_COMPILE_REQUIRED`. Its nearby upstream work continues to
improve async graphics properties and compiler-worker scaling, but no exact
cache-hit-only preload slice was available to cherry-pick.

Relevant research directions were also reviewed:

- direct binary translation reports large proof-of-concept gains over QEMU
  TCG, but is not direct RPCSX evidence: <https://arxiv.org/abs/2501.03427>;
- learned DBT translation rules report average gains on SPEC and real
  applications: <https://arxiv.org/abs/2402.09688>;
- selective native-function offload reports large wins for identified hot
  functions: <https://arxiv.org/abs/2512.00487>;
- verified peephole generalization offers a path to safer ARM64 codegen
  improvements: <https://arxiv.org/abs/2603.18477>;
- phase-specific heterogeneous mobile execution supports phase-aware thermal
  policy, though its Snapdragon 8 Elite NPU results do not directly transfer
  to this Adreno/Vulkan emulator path: <https://arxiv.org/abs/2606.27906>; and
- shared JIT-code caching reduced JIT time and memory in an older Android
  study, reinforcing the value of warm-cache reuse mechanisms:
  <https://arxiv.org/abs/1810.09555>.

The immediate actionable lane is the Vulkan cache-hit-only preload below.
The strongest longer-term CPU lane is exact-signature selective native/HLE
handling for proven hot PPU/SPURS functions, followed by verified ARM64
peepholes. Broad SPU-to-GPU offload remains rejected for Eternal Sonata: saved
probes have no RSX-local byte traffic and introduce readback/synchronization
risk.

## Implementation

New experimental Android property:

`debug.rpcsx.thor.vk_preload_cache_hits_only=off|on`

It is default-off. Enabling it still requires all of these runtime facts:

1. the property explicitly requests `on`;
2. a nonempty driver pipeline-cache seed was loaded and validated;
3. the device exposes and the logical device enables
   `pipelineCreationCacheControl`; and
4. the pipeline belongs to cached graphics-pipeline preload, not an ordinary
   runtime or async placeholder.

The feature query uses the Vulkan 1.3 core route when available and the
extension route below 1.3. The extension is requested only when needed.
Feature Doctor records both extension presence and the actual feature bit.

For the narrow preload scope, the compiler copies the graphics create info and
adds `VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT`. Cache hits are
created and stored normally. `VK_PIPELINE_COMPILE_REQUIRED` is counted as a
deferred miss, returns no pipeline, and is not fatal. An optional Vulkan cache
trait removes only that null preload placeholder, so a later game request goes
through the existing normal compile path. Other backends and ordinary async
placeholders are unchanged.

Compiler shutdown emits:

`Vulkan preload cache-hits-only summary: hits=<n>, deferred_misses=<n>.`

If the property, warm seed, or feature requirement is absent, the exact prior
full preload path remains. The route harness captures the effective property
and resets it to `off` before launch and after success or failure. The
no-launch installer records it with the other experiment controls.

## Host Verification

No Thor or ADB action ran. The following passed:

- ARM64 RelWithDebInfo native build;
- optimized ARM64-only ThorTest APK build;
- all 23 `test_thor_*.ps1` contracts;
- Vulkan cache-hit-only warm-seed, feature, preload-scope, runtime-fallback,
  and cleanup contract;
- existing Vulkan pipeline cache and RSX preload contracts;
- multi-sensor thermal guard and visual route gates;
- JIT cache, PPU, SPU, ABI, optimized-variant, and no-launch contracts;
- APK ARM64 library contract;
- core export surface: 34 defined dynamic symbols, 585 explicit relocations,
  391 jump slots, and 44,227 encoded relocation bytes;
- packaged stripped-core SHA-256 identity against the APK entry;
- binary strings for the property, feature doctor, each safe fallback,
  enable row, and hit/deferred-miss summary; and
- `git diff --check`.

## Exact Host-only Candidate

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,578,798` bytes
- APK SHA-256:
  `C8ED84B8D03DB8CD2C72F774AF8F2438450A29D3EF70BB5CFB6B68CB91F38522`
- merged ARM64 core size: `1,305,733,688` bytes
- merged ARM64 core SHA-256:
  `C84683A69E8531BB3A5038CDAAB13BDFB382F1E0A181261E021E8C6E4D1A52C9`
- packaged stripped core size: `62,854,696` bytes
- packaged stripped core SHA-256:
  `37C836739E46ADC7E34298F7FA84529D9C5B747177DFE9D6E6BC4CFA269C574C`

This candidate also contains all previously committed ARM64, JIT-cache, and
Android raw-cache work through commit `b2fa4ca6f`.

## Device Boundary And Proof Plan

The candidate is uninstalled and device-unmeasured. RPCSX remains stopped.
No FPS, time-to-title, frame pacing, flicker, gameplay correctness, sustained
temperature, or energy improvement is claimed.

A later cool-device sequence may proceed only as separate bounded rounds:

1. strict no-launch thermal gate, exact install, exact on-device APK hash, and
   stopped PID; no launch in that round;
2. after independent cooling, one guarded startup with the property still
   `off` to establish the exact candidate control;
3. after independent cooling, one guarded startup with the property `on`,
   requiring a validated nonempty seed, enabled feature, and the
   `hits/deferred_misses` summary; and
4. grant any win only if comparable time-to-title and thermal evidence improve
   while field, menu, and first-battle visuals remain correct and fatal,
   device-loss, and unknown-draw scans stay clean.

Rollback is immediate: leave or set
`debug.rpcsx.thor.vk_preload_cache_hits_only=off`. That is the default and
restores the existing full preload path.

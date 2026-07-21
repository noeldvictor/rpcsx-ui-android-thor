$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$asmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rx/include/rx/asm.hpp"
$nv406ePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/NV47/HW/nv406e.cpp"
$vkTypesPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKGSRenderTypes.hpp"

function Get-ContractSegment {
    param(
        [string]$Source,
        [string]$StartMarker,
        [string]$EndMarker
    )

    $start = $Source.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Missing hardware-wait contract marker: $StartMarker"
    }

    $end = $Source.IndexOf(
        $EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) {
        throw "Missing hardware-wait contract marker: $EndMarker"
    }

    return $Source.Substring($start, $end - $start)
}

function Assert-FragmentsInOrder {
    param(
        [string]$Name,
        [string]$Source,
        [string[]]$Fragments
    )

    $cursor = 0
    foreach ($fragment in $Fragments) {
        $index = $Source.IndexOf(
            $fragment, $cursor, [StringComparison]::Ordinal)
        if ($index -lt 0) {
            throw "$Name is missing or misorders: $fragment"
        }
        $cursor = $index + $fragment.Length
    }
}

$asmSource = Get-Content -LiteralPath $asmPath -Raw
$oneShot = Get-ContractSegment -Source $asmSource `
    -StartMarker "inline void spin_on_cacheline_once" `
    -EndMarker "inline void spin_wait"
$spinWait = Get-ContractSegment -Source $asmSource `
    -StartMarker "inline void spin_wait" `
    -EndMarker "// Align to power of 2"

Assert-FragmentsInOrder -Name "AArch64 one-shot cacheline wait" -Source $oneShot -Fragments @(
    "#if defined(ARCH_ARM64)",
    'ldaxr %w0, %1',
    "if (std::bit_cast<wait_type>(value) != old_value)",
    '__asm__ volatile("clrex"',
    '__asm__ volatile("wfe"',
    '__asm__ volatile("clrex"',
    "#else",
    "std::this_thread::yield();"
)

Assert-FragmentsInOrder -Name "AArch64 predicate cacheline wait" -Source $spinWait -Fragments @(
    "while (true)",
    "if (predicate(read_mem()))",
    "#if defined(ARCH_ARM64)",
    'ldaxr %w0, %1',
    "if (predicate(static_cast<value_type>(value)))",
    '__asm__ volatile("clrex"',
    '__asm__ volatile("wfe"',
    '__asm__ volatile("clrex"',
    "#else",
    "pause();"
)

$nv406eSource = Get-Content -LiteralPath $nv406ePath -Raw
$semaphoreAcquire = Get-ContractSegment -Source $nv406eSource `
    -StartMarker "void semaphore_acquire" `
    -EndMarker "void semaphore_release"
Assert-FragmentsInOrder -Name "RSX semaphore one-shot wait" -Source $semaphoreAcquire -Fragments @(
    "if (RSX(ctx)->external_interrupt_lock",
    "RSX(ctx)->cpu_wait({});",
    "continue;",
    "RSX(ctx)->on_semaphore_acquire_wait();",
    "rx::spin_on_cacheline_once(sema, sema.load(), 100);"
)

$vkTypesSource = Get-Content -LiteralPath $vkTypesPath -Raw
$flushTask = Get-ContractSegment -Source $vkTypesSource `
    -StartMarker "struct flush_request_task" `
    -EndMarker "struct present_surface_info"

if ([regex]::Matches($flushTask, [regex]::Escape("rx::spin_wait(")).Count -ne 2) {
    throw "Expected both Vulkan flush-request waits to use the hardware helper."
}

foreach ($legacy in @(
    "while (num_waiters.load() != 0)",
    "while (pending_state.load())"
)) {
    if ($flushTask.Contains($legacy)) {
        throw "Legacy Vulkan polling loop remains: $legacy"
    }
}

Write-Output "Thor ARM64 hardware-wait contract passed: cacheline-change waits use load-exclusive plus WFE, preserve debugger handling, and avoid broad busy-wait replacement."

# Eternal Sonata 0x25cc Coverage Gap

- Generated: 2026-05-26T15:16:19.9284550-04:00
- Verify run: `20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows`
- Skip run: `20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows`
- Latest atlas 0x25cc bucket: `4340` records across `6` valid field runs, `6.86 GB`, `0 B` RSX-local.
- Classification: `analysis`, `spu-hle-25cc-coverage-gap`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.

## Coverage

| Mode | Hot 0x25cc | Top EA | Exact verify shape | Verify share | Shadow bytes | Skip bytes | Skip/Hot | Skip/Exact | Mismatch | Dst changed | Title avg FPS |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Verify | 501.28 MB / 312 rec | `0x9e4000` | 72.89 MB / 4665 hits | 14.54% | 4.86 MB | 0 B | 0.00% | 0.00% | 0 | 0 | 116.57 |
| Skip | 573.70 MB / 356 rec | `0x9e4000` | 83.20 MB / 5325 hits | 14.50% | 5.55 MB | 5.55 MB | 0.97% | 6.67% | 0 | 0 | 111.33 |

## Reading

- The exact guarded skip shape remains correctness-clean: the title-CSV skip run has `0` mismatches, `0` destination changes, `0` skip misses, and `5.55 MB` of proven redundant copy removal.
- The same skip removes only `0.97%` of that run's total hot `0x25cc` bytes and `6.67%` of the exact verifier-shape bytes.
- Against the refreshed atlas bucket (`6.86 GB`), the title-CSV skip's `5.55 MB` is only `0.08%` of observed `0x25cc` traffic.
- The hot `0x25cc` row's top EA is `0x9e4000`, while the exact skip shape is fixed to `lsa=0x3b000` / `eal=0xa1c000`; this explains why the clean skip did not become a measured speed win.
- Next useful `0x25cc` work should broaden verify-only coverage around the dynamic MFC / `0x9e4000` pattern families or codegen dispatch overhead. Do not rerun the exact `0xa1c000` skip expecting 200%.

# Handoff: Porting ZFP lossy compression into the `thermals` RAMS branch

**Audience:** Claude Code running on the **build machine** (where RAMS is compiled and run).
**Author context:** Written from the analysis machine, which only *reads* RAMS output. The read
side (Python) is already set up there; everything in this document is the *build/run* side that
must happen on your machine.

**Goal:** Enable per-variable ZFP lossy compression of RAMS lite-file (`a-L-*`) output on the
`thermals` branch, and make sure the resulting files can be built and written correctly.

---

## 1. What this feature is, in one paragraph

RAMS gets optional **ZFP fixed-accuracy compression** wired into its HDF5 output path via the
**H5Z-ZFP** HDF5 filter plugin (HDF5 filter id **32013**). It applies **only to lite files**
(`a-L-*`), **only to real/double array variables**, and each lite variable gets its own accuracy
tolerance set positionally in the RAMSIN namelist via a new array **`ACC_LT_VAR`** (parallel to
`LITE_VARS`). An accuracy of `0.` means "lossless" (falls back to the existing shuffle+gzip path);
a positive value is the ZFP **absolute error tolerance** for that variable. Full analysis files
(`a-A-*`) and mean files are never lossy-compressed.

---

## 2. Where the code lives / upstream status (already settled — no action needed)

- The feature already exists as a set of commits on the local branch **`lossy_compression`** in the
  `RAMS_cd` repo. Those are the commits you will merge into `thermals`.
- Upstream INCUS (`git@github.com:CSU-INCUS/RAMS.git`) has a branch `zfp-compression-output`, but it
  is the **older 2022 seed** of this exact feature (last real change Sep 2022). Our `lossy_compression`
  branch is **ahead** of it (it adds a "fail loudly if the ZFP library isn't compiled in" guard, the
  `H5Z_ZFP_ROOT` naming, and the `include.mk` wiring). **There is nothing newer to pull from upstream.**
- `incus/prod` carries the same feature rebased onto RAMS v6.3.04 plus unrelated INCUS work; not worth
  chasing just for ZFP.

---

## 3. What the code change actually does (files touched by `lossy_compression`)

All of these are already committed on `lossy_compression`; you get them via the merge in §4.

| File | Change |
|---|---|
| `src/lib/hdf5_f2c.c` | `fh5d_write` gains `enable_truncation` (int) + `truncation_accuracy` (float). When truncation is on and `-DENABLE_ZFP_COMPRESSION` was compiled in: sets chunking, calls `H5Pset_zfp_accuracy_cdata(accuracy, ...)`, attaches filter with `H5Pset_filter(propid, H5Z_FILTER_ZFP, H5Z_FLAG_MANDATORY, ...)`. If truncation requested but library not compiled in → errors out (`hdferr=-9999`) instead of silently writing lossless. Otherwise falls through to the existing lossless shuffle+deflate path. `#include "H5Zzfp_plugin.h"` guarded by `#ifdef ENABLE_ZFP_COMPRESSION`. |
| `src/lib/hdf5_utils.f90` | `shdf5_orec` gains a `zfp_accuracy` argument. Maps `0.`→lossless, `>0.`→ZFP on, `<0.`→fatal stop. Only passes the enable flag through for the `ra`/`da` (real/double **array**) cases; scalars & int/char/logical always pass 0. |
| `src/memory/var_tables.f90` | `var_tables_r` type gains `real(kind=4) :: var_acc` (per-variable accuracy; 32-bit to match the C side). |
| `src/memory/vtab_fill.f90` | When a var matches the lite list, copies `lite_var_acc(nvl)` into `vtab_r%var_acc`. (Also has a debug `print*` you may want to delete.) |
| `src/io/anal_write.f90` | Sets `zfp_accuracy = vtab_r%var_acc` **only for `LITE`** output; forces `0` for `INST`/`MEAN`/`BOTH`. Threads it into both `shdf5_orec` calls. |
| `src/io/io_params.f90` | New module var `real(kind=4) :: lite_var_acc(maxlite)`. |
| `src/io/rname.f90` | New namelist entry `ACC_LT_VAR` in the `$MODEL_FILE_INFO` group; `nvstrt` 77→78; `varsetf` handler. |
| `src/mpi/mpass_init.f90` | Broadcasts `LITE_VAR_ACC` to worker ranks (pack/unpack + buffer-size accumulator). |
| `src/mksfc/mksfc_*.f90`, `src/isan/isan_io.f90`, `src/isan/write_varf.f90` | Mechanical: every other `shdf5_orec` caller updated to pass `zfp_accuracy=0.` (the signature changed, so all callers must pass it). |
| `include.mk.example` | Reference wiring for `H5Z_ZFP_ROOT` + `-DENABLE_ZFP_COMPRESSION` (see §6). |

---

## 4. Merge `lossy_compression` → `thermals` (exactly one trivial conflict)

The `lossy_compression` branch currently only exists locally on the analysis machine's `RAMS_cd`
checkout. **First make sure your build-machine checkout can see it:**

```bash
# On the analysis machine (or wherever lossy_compression lives), push it once:
git push origin lossy_compression
# On the build machine:
git fetch origin
```

Then merge on the build machine:

```bash
git checkout thermals
git merge --no-ff origin/lossy_compression      # or lossy_compression if it's local
```

**There is exactly one conflict, in `src/io/rname.f90`**, on the parameter-count line:

```fortran
<<<<<<< HEAD  (thermals: added wind-tendency INDAT vars)
integer, parameter ::nvgrid=37,nvstrt=77,nvindat=165,nvsound=10
=======
integer, parameter ::nvgrid=37,nvstrt=78,nvindat=147,nvsound=10   (lossy: added ACC_LT_VAR to START)
>>>>>>> lossy_compression
```

**Resolution — take `nvstrt` from lossy and `nvindat` from thermals:**

```fortran
integer, parameter ::nvgrid=37,nvstrt=78,nvindat=165,nvsound=10
```

Rationale: `nvstrt` counts entries in the `START` (`$MODEL_FILE_INFO`) namelist array, which
lossy grew by one (`ACC_LT_VAR`). `nvindat` counts the `INDAT` array, which thermals grew for the
wind-tendency inputs. They are independent arrays, so both increments are kept. The `'ACC_LT_VAR'`
entry in the `START` data array and the `IF(VR.EQ.'ACC_LT_VAR')` handler merge cleanly on their own
— this counter line is the only conflict. Then:

```bash
git add src/io/rname.f90
git commit           # completes the merge
```

Everything else (`io_params.f90`, `mpass_init.f90`, and all the callers) auto-merges cleanly.

---

## 5. Build the ZFP stack (zfp + H5Z-ZFP) against **your** HDF5

> ⚠️ **Match your HDF5.** The H5Z-ZFP filter must be built against the *same* HDF5 your RAMS links.
> Find it in your real `include.mk` (`HDF5_ROOT=...`) and confirm the version:
> ```bash
> $HDF5_ROOT/bin/h5dump --version
> ```
> On the analysis machine's mirror this happened to be HDF5 **2.0.0**, but you indicated your build
> machine is **not** on 2.0.0. Whatever it is (1.10 / 1.12 / 1.14), build the filter against it.
> H5Z-ZFP release **v1.1.1** builds cleanly against HDF5 1.8–1.14. **If** you ever do hit HDF5 2.0.0,
> test v1.1.1 first and fall back to H5Z-ZFP `master`/newest tag if the 2.0 API bites.

Pick an install prefix, e.g. `H5ZZFP_ROOT=$HOME/rams_build/install/h5z_zfp` and
`ZFP_ROOT=$HOME/rams_build/install/zfp`.

### 5a. zfp (the compressor itself) — skip if you already have a libzfp you trust

```bash
git clone https://github.com/LLNL/zfp.git && cd zfp
git checkout 1.0.1                          # matches what the analysis machine reads with
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=$ZFP_ROOT -DBUILD_SHARED_LIBS=ON
cmake --build build -j && cmake --install build
# → $ZFP_ROOT/include/zfp.h , $ZFP_ROOT/lib(64)/libzfp.so
```

### 5b. H5Z-ZFP (the HDF5 filter)

```bash
git clone https://github.com/LLNL/H5Z-ZFP.git && cd H5Z-ZFP
git checkout v1.1.1
make CC=gcc HDF5_DIR=$HDF5_ROOT ZFP_DIR=$ZFP_ROOT PREFIX=$H5ZZFP_ROOT all
make CC=gcc HDF5_DIR=$HDF5_ROOT ZFP_DIR=$ZFP_ROOT PREFIX=$H5ZZFP_ROOT install
```

Produces (this is what the `include.mk.example` in the branch already expects):
- `$H5ZZFP_ROOT/include/` — `H5Zzfp_plugin.h`, `H5Zzfp.h`, `H5Zzfp_lib.h`, …
- `$H5ZZFP_ROOT/lib/libh5zzfp.a` — static lib (only needed if you link the filter directly)
- `$H5ZZFP_ROOT/plugin/libh5zzfp.so` — **the runtime plugin** (this is the important one)

Notes:
- H5Z-ZFP's Makefile keys off `HDF5_DIR` and `ZFP_DIR`; if your zfp install puts libs in `lib64`,
  or headers in `inc` vs `include`, peek at `H5Z-ZFP/config.make` and adjust `ZFP_DIR`/vars.
- Build the filter with a compiler compatible with the one that built your HDF5. Plain `gcc` for the
  plugin is normally fine even if RAMS itself is built with `mpicc`/`mpif90`.

---

## 6. Wire ZFP into your **real** `include.mk` (not `.example`)

RAMS only compiles the C-side ZFP code path when `-DENABLE_ZFP_COMPRESSION` is defined, and it needs
the H5Z-ZFP header on the include path. Edit your active `include.mk`:

```make
# near HDF5_ROOT:
H5Z_ZFP_ROOT=/home/<you>/rams_build/install/h5z_zfp

# add the ZFP include dir to the HDF5 includes:
HDF5_INCS=-I$(HDF5_ROOT)/include -I$(H5Z_ZFP_ROOT)/include

# add the enable flag to the C options (keep your existing flags):
C_OPTS=-O3 -DUNDERSCORE -DLITTLE -std=gnu99 -DENABLE_PARALLEL_COMPRESSION -w -DENABLE_ZFP_COMPRESSION
```

You do **not** need to add `-lh5zzfp` to the link line: the code uses the H5Z-ZFP *plugin* interface
(`H5Zzfp_plugin.h`, whose `H5Pset_zfp_accuracy_cdata` is inline) plus core `H5Pset_filter`, and the
filter itself is loaded dynamically at runtime (§7). Then rebuild RAMS.

> **HDF5 capability check (lossless fallback):** the `ACC_LT_VAR=0.` path and all non-lite writes go
> through `H5Pset_shuffle`+`H5Pset_deflate`, which require your HDF5 to have the **deflate (gzip)**
> filter compiled in. If your current RAMS runs already produce compressed output, you're fine. (Heads
> up: the analysis-machine HDF5 2.0.0 mirror was built *without* deflate — verify `H5_HAVE_FILTER_DEFLATE`
> is defined in `$HDF5_ROOT/include/H5pubconf.h` on your build machine.)

---

## 7. Make RAMS find the filter at **run** time

The filter is a dynamically loaded HDF5 plugin. Two options — pick one:

- **Easiest:** drop the plugin into HDF5's default plugin dir so it auto-loads with no env var. HDF5's
  compiled-in default dir is in `$HDF5_ROOT/include/H5pubconf.h` as `H5_DEFAULT_PLUGINDIR` (on the
  analysis mirror it was `$HDF5_ROOT/lib/plugin`):
  ```bash
  mkdir -p $HDF5_ROOT/lib/plugin
  cp $H5ZZFP_ROOT/plugin/libh5zzfp.so $HDF5_ROOT/lib/plugin/
  ```
- **Or** set the env var in your run script / job submission:
  ```bash
  export HDF5_PLUGIN_PATH=$H5ZZFP_ROOT/plugin
  ```

Also make sure `libzfp.so` is findable at run time (it's a dependency of the plugin), unless you
static-linked zfp:
```bash
export LD_LIBRARY_PATH=$ZFP_ROOT/lib:$LD_LIBRARY_PATH   # or lib64
# verify:
ldd $H5ZZFP_ROOT/plugin/libh5zzfp.so | grep zfp
```

---

## 8. RAMSIN usage

In the `$MODEL_FILE_INFO` group, add an `ACC_LT_VAR` line positionally matched to `LITE_VARS`
(same count as `NLITE_VARS`). `0.` = lossless for that variable; positive = ZFP absolute accuracy.

```fortran
NLITE_VARS  = 7,
LITE_VARS   = 'GLAT','GLON','TOPT','PATCH_AREA', 'RV','THETA','WP',
ACC_LT_VAR  =  0.,   0.,    0.,    0.,           0.1, 0.01,   0.001,
```

Start with **all `0.`** for a first build/run to confirm bit-exact behavior and that nothing broke,
then introduce tolerances one variable at a time. Only `a-L-*` files are affected.

---

## 9. Verification checklist (build machine)

1. `grep ENABLE_ZFP_COMPRESSION include.mk` → present in `C_OPTS`. RAMS rebuilds without error.
2. Run with **all `ACC_LT_VAR=0.`** → lite files still readable, byte-for-byte like before ZFP.
3. Run with one positive accuracy (e.g. `THETA=0.01`) → run completes; the lite file's `THETA`
   dataset now carries filter **32013**. Sanity check with `h5dump -p -H a-L-...h5 | grep -i zfp`
   or `h5ls -v`.
4. Deliberately break it to confirm the guard: build **without** `-DENABLE_ZFP_COMPRESSION` but set
   `ACC_LT_VAR>0.` → RAMS should stop with the "ZFP compression requested, but ZFP library not
   included" error rather than silently writing lossless. (Then rebuild with the flag.)
5. Transfer one lossy lite file to the analysis machine and confirm it reads (see §10).

---

## 10. Reading the compressed output (analysis machine — ALREADY DONE, for reference)

No further action needed on the analysis side; documented here so both machines agree.

- `hdf5plugin` was added to the thermals pixi env (`hdf5plugin >=6.0.0`, resolved to **6.0.0**;
  bundles the ZFP filter, id 32013, built against libhdf5 1.14.6 — h5py 3.16.0).
- Read pattern in notebooks/scripts — **import `hdf5plugin` before opening any file:**
  ```python
  import hdf5plugin          # registers filter 32013 with libhdf5; must be imported before open
  import h5py, xarray as xr
  ds = xr.open_dataset("a-L-....h5", engine="h5netcdf")   # or h5py.File(...)
  ```
- Verified end-to-end on the analysis machine: a ZFP-accuracy-compressed float32 field round-trips —
  filter 32013 decodes, the accuracy tolerance is honored (max abs err 0.002 for target 0.01), ~4x
  compression on synthetic data. Cross-version is fine: your writer (H5Z-ZFP v1.1.x + zfp 1.0.x)
  and this reader (hdf5plugin's bundled zfp 1.0.x) interoperate because ZFP is identified by filter
  id 32013 and zfp 1.x streams are compatible.

---

## 11. Known rough edges to clean up (optional)

- `src/memory/vtab_fill.f90` and the C file have leftover `print*` / commented debug statements from
  development — safe to delete once you trust the path.
- The implementation only supports ZFP **fixed-accuracy** mode (no rate/precision modes). That's
  usually what you want for scientific fields, but note it if someone asks for a fixed compression
  ratio.

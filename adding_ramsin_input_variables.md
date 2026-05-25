# Guide: Adding Input Variables to RAMSIN

This document explains how to add new input variables to the RAMS model that can be read from the RAMSIN namelist file.

## Overview

RAMSIN is the primary input file for RAMS, containing Fortran namelists that control model configuration. Adding a new input variable requires modifications to several files in a specific pattern.

## Example: Adding IUVWTEND

This guide uses `IUVWTEND` (a flag to control output of U/V/W tendency diagnostic variables) as a concrete example.

## Variable Name Length Limit

**IMPORTANT**: RAMSIN variable names are limited to **16 characters maximum**.

This limit is defined in [src/io/rname.f90](src/io/rname.f90:30):
```fortran
character(len=16) :: grids(nvgrid),start(nvstrt),indat(nvindat),sound(nvsound)
```

To change this limit, modify the `len=16` parameter in rname.f90. However, be aware that this may affect compatibility with existing RAMSIN files and tools.

## Step-by-Step Process

### 1. Declare the Variable in Appropriate Module

Choose the module where the variable logically belongs:
- **io_params.f90** - I/O and output control variables
- **micphys.f90** - Microphysics-related variables
- **mem_grid.f90** - Grid configuration variables
- etc.

**File**: [src/io/io_params.f90](src/io/io_params.f90) (for IUVWTEND)

**Action**: Add the variable declaration:
```fortran
integer :: ioutput,iclobber,nlite_vars,iuvwtend
```

**General Pattern**:
- Integer variables: `integer :: variable_name`
- Real variables: `real :: variable_name`
- Character variables: `character(len=N) :: variable_name`
- Arrays: Add dimension specifications as needed

### 2. Increment the Namelist Counter

**File**: [src/io/rname.f90](src/io/rname.f90)

**Action**: Increment the counter for the appropriate namelist group (line ~28):

```fortran
! Before (147 variables in INDAT)
integer, parameter ::nvgrid=37,nvstrt=77,nvindat=147,nvsound=10

! After (148 variables in INDAT)
integer, parameter ::nvgrid=37,nvstrt=77,nvindat=148,nvsound=10
```

**Namelist Counters**:
- `nvgrid` - Number of variables in `$MODEL_GRIDS` namelist
- `nvstrt` - Number of variables in `$MODEL_FILE_INFO` / `$MODEL_OPTIONS` namelists
- `nvindat` - Number of variables in physics/dynamics namelists (INDAT)
- `nvsound` - Number of variables in `$MODEL_SOUND` namelist

**⚠️ CRITICAL**: You must increment the appropriate counter or the namelist reading will fail!

### 3. Add Variable to DATA Array

**File**: [src/io/rname.f90](src/io/rname.f90)

**Action**: Add the variable name to the appropriate DATA array (lines ~40-80):
```fortran
DATA INDAT/  &
     ...
     ,'ICHECKMIC','ITRACER','ITRACHIST','IMBUDGET','IUVWTEND','IRIME','IPLAWS'      &
     ...
```

**General Pattern**:
- Variables are organized by namelist group (GRIDS, START, INDAT, SOUND)
- Add your variable name in **UPPERCASE** as a character string
- Place it logically near related variables
- Ensure proper line continuation with `&`

**Namelist Groups**:
- `GRIDS` - Grid configuration (resolution, nesting, domain size)
- `START` - Initialization and I/O settings
- `INDAT` - Physics options and parameters
- `SOUND` - Atmospheric sounding data

### 4. Add Variable Reading Logic

**File**: [src/io/rname.f90](src/io/rname.f90)

**Action**: Add a conditional statement with appropriate setter call (lines ~200-400):
```fortran
 IF(VR.EQ.'IMBUDGET')     CALL varseti (VR,IMBUDGET,NV,1,II,0,3)
 IF(VR.EQ.'IUVWTEND')     CALL varseti (VR,IUVWTEND,NV,1,II,0,1)
 IF(VR.EQ.'IRIME')        CALL varseti (VR,IRIME,NV,1,II,0,1)
```

**General Pattern for Integer Variables**:
```fortran
IF(VR.EQ.'VARNAME')  CALL varseti (VR,variable_name,NV,1,II,min_value,max_value)
```

**General Pattern for Real Variables**:
```fortran
IF(VR.EQ.'VARNAME')  CALL varsetf (VR,variable_name,NV,1,FF,min_value,max_value)
```

**General Pattern for Character Variables**:
```fortran
IF(VR.EQ.'VARNAME')  CALL varsetc (VR,variable_name,NV,1,CC)
```

**Parameters Explained**:
- `VR` - Variable name being read
- `variable_name` - The actual Fortran variable
- `NV` - Number of values
- `1` - Array index
- `II`/`FF`/`CC` - Input value (integer/float/character)
- `min_value`, `max_value` - Valid range (for varseti/varsetf only)

**Important Notes**:
- The `varseti`/`varsetf` calls handle both reading from RAMSIN and setting default values
- If the variable is not specified in RAMSIN, the variable retains its default value from module initialization (typically 0, 0.0, or '')
- **You do NOT need to explicitly initialize the variable in opspec.f90 or elsewhere** - the namelist reading system handles this

### 5. Add Variable to Print Statement

**File**: [src/io/rname.f90](src/io/rname.f90)

**Action**: Add the variable to the print statement (lines ~500-600):
```fortran
 print*  &
 ,'ICHECKMIC=',ICHECKMIC             &
 ,'IMBUDGET=',IMBUDGET               &
 ,'IUVWTEND=',IUVWTEND               &
 ,'IRIME=',IRIME                     &
```

**General Pattern**:
```fortran
 ,'VARNAME=',variable_name           &
```

This prints the variable value to the output log when RAMS starts, allowing verification of input values.

### 6. Use the Variable in Code

Once declared and registered, the variable can be used anywhere in the code by:

1. Adding a `use` statement to access the module:
```fortran
use io_params, only: iuvwtend
```

2. Using the variable in conditional logic:
```fortran
if(iuvwtend>=1) then
  ! Perform action
endif
```

**⚠️ IMPORTANT - Variable Declaration Location**:

When using variables inside loops or conditional blocks, declare them at the **top of the subroutine**, not inside the loop:

**WRONG** (non-standard Fortran):
```fortran
do k = 2,m1-1
   real :: temp_value  ! ILLEGAL - can't declare inside loop
   temp_value = calculate_something()
   array(k) = temp_value
enddo
```

**CORRECT**:
```fortran
! Declare at top of subroutine
integer :: k
real :: temp_value

! Use in loop
do k = 2,m1-1
   temp_value = calculate_something()
   array(k) = temp_value
enddo
```

## Complete Example: IUVWTEND

### Files Modified for IUVWTEND

1. **[src/io/io_params.f90](src/io/io_params.f90:13)**
   - Declared: `integer :: ioutput,iclobber,nlite_vars,iuvwtend`

2. **[src/io/rname.f90](src/io/rname.f90)**
   - Incremented counter (line 28): `nvindat=148` (was 147)
   - Added to DATA array (line 70): `'IUVWTEND'`
   - Added varseti call (line 331): `IF(VR.EQ.'IUVWTEND') CALL varseti (VR,IUVWTEND,NV,1,II,0,1)`
   - Added to print (line 519): `,'IUVWTEND=',IUVWTEND`

3. **Usage in multiple files**:
   - [src/memory/mem_basic.f90](src/memory/mem_basic.f90) - Controls allocation of tendency arrays
   - [src/core/radvc.f90](src/core/radvc.f90) - Controls advection tendency output
   - [src/core/raco.f90](src/core/raco.f90) - Controls pressure gradient tendency output
   - [src/core/coriolis.f90](src/core/coriolis.f90) - Controls Coriolis tendency output

### Using IUVWTEND in RAMSIN

Add to your RAMSIN file in the appropriate namelist:
```fortran
$MODEL_FILE_INFO
 ...
 IUVWTEND = 1
 ...
$END
```

Valid values:
- `0` - Do not output U/V/W tendency diagnostics (default)
- `1` - Output U/V/W tendency diagnostics to analysis files

## Common Patterns

### Integer Flag (0/1)
```fortran
! Range: 0 to 1
CALL varseti (VR,variable_name,NV,1,II,0,1)
```

### Integer with Multiple Options (0/1/2/3)
```fortran
! Range: 0 to 3
CALL varseti (VR,variable_name,NV,1,II,0,3)
```

### Floating Point with Range
```fortran
! Range: 0.0 to 1000.0
CALL varsetf (VR,variable_name,NV,1,FF,0.,1000.)
```

### Floating Point with Large Range
```fortran
! Range: 0.0 to very large
CALL varsetf (VR,variable_name,NV,1,FF,0.,1.E20)
```

### Character/String Variable
```fortran
! No range checking
CALL varsetc (VR,variable_name,NV,1,CC)
```

## Common Mistakes and How to Avoid Them

### ❌ Mistake 1: Forgetting to Increment Namelist Counter

**Problem**: Adding a variable to DATA array without incrementing the counter causes array bounds errors.

**Solution**: Always increment the appropriate counter (nvgrid, nvstrt, nvindat, or nvsound) when adding a variable.

### ❌ Mistake 2: Declaring Variables Inside Loops

**Problem**: Modern Fortran compilers may accept this, but it's non-standard and causes portability issues.

**Solution**: Always declare variables at the top of the subroutine, before any executable statements.

### ❌ Mistake 3: Initializing Variables in opspec.f90

**Problem**: Variables read from RAMSIN don't need explicit initialization - the varseti/varsetf calls handle defaults.

**Solution**: Only initialize variables in opspec.f90 if they are **computed** or **derived** values, not user inputs. For user inputs from RAMSIN, the namelist system handles defaults.

**Exception**: Variables that depend on other settings (like turning off microphysics variables when `level < 3`) should be initialized in opspec.f90.

### ❌ Mistake 4: Wrong Module for Variable

**Problem**: Placing a variable in the wrong module makes code confusing and may cause circular dependencies.

**Solution**:
- I/O control → `io_params`
- Microphysics → `micphys`
- Grid config → `mem_grid`
- Radiation → `mem_radiate`

### ❌ Mistake 5: Missing Use Statement

**Problem**: Forgetting to add `use module_name` causes "undefined variable" compilation errors.

**Solution**: In every subroutine that uses the variable, add:
```fortran
use module_name, only: variable_name
```

## Troubleshooting

### Variable Not Being Read
- Check that variable name is in DATA array (rname.f90)
- Verify variable name is spelled consistently (UPPERCASE in DATA array)
- Check that IF(VR.EQ.'...') statement exists
- Ensure variable is in correct namelist group in RAMSIN
- **Check that namelist counter was incremented**

### Compilation Errors
- Verify variable is declared in source module
- Check that `use` statements reference correct module
- Ensure variable type matches setter function (varseti/varsetf/varsetc)
- **Check that variable declarations are at top of subroutine, not inside loops**

### Value Out of Range
- Check min/max values in varseti/varsetf call
- Ensure RAMSIN value is within allowed range
- Model will report error and stop if value is invalid

### Variable Name Too Long
- Maximum length is 16 characters
- Shorten the variable name or modify the limit in rname.f90

### Array Bounds Errors in Namelist Reading
- **Check that you incremented the namelist counter** (nvgrid, nvstrt, nvindat, or nvsound)
- The counter must match the actual number of variables in the DATA array

## Best Practices

1. **Choose descriptive names** - Use clear, meaningful variable names that indicate purpose
2. **Follow naming conventions** - Use existing variable names as templates (e.g., I* for integer flags)
3. **Group related variables** - Place new variables near similar ones in all files
4. **Document in comments** - Add comments explaining the variable's purpose
5. **Set appropriate defaults** - Variables typically default to 0, 0.0, or '' from module initialization
6. **Validate ranges** - Use min/max values in varseti/varsetf to prevent invalid inputs
7. **Increment counters** - Always update the namelist counter when adding variables
8. **Declare at top** - Put all variable declarations at the top of subroutines
9. **Test thoroughly** - Verify variable is read correctly and used as intended

## Summary: Required Steps

For quick reference, here are the essential steps:

1. ✅ Declare variable in appropriate module (e.g., io_params.f90)
2. ✅ **Increment namelist counter** in rname.f90 (nvindat, nvstrt, etc.)
3. ✅ Add variable name to DATA array in rname.f90
4. ✅ Add varseti/varsetf/varsetc call in rname.f90
5. ✅ Add to print statement in rname.f90
6. ✅ Use variable in code with proper `use` statements
7. ✅ Declare any temporary variables at top of subroutines

**Note**: Do NOT initialize in opspec.f90 unless the variable is computed/derived (not a direct user input).

## References

- [RAMS-Namelist.pdf](docs/RAMS-Namelist.pdf) - Complete namelist reference
- [rname.f90](src/io/rname.f90) - Namelist reading implementation
- [io_params.f90](src/io/io_params.f90) - I/O parameter declarations
- [micphys.f90](src/micro/micphys.f90) - Microphysics parameter declarations

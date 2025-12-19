# Debugging Volumetric Heating Implementation

## Summary
Added extensive debugging output to `volumetric_heating` subroutine in `src/surface/ruser.f90`.

## Debug Output Added

### At Initialization (t=0):
- Grid configuration
- Spatial extent of heating region
- Timing parameters
- Grid spacing (deltax, deltaz)

### At t=1s, 300s, 600s, 1200s:
- temporal_factor
- Heating geometry (bubctrx, bubctry, bubradx, bubrady)
- Attenuation length
- Maximum heating_wm2 (W/m²) and location
- Maximum heating_rate (K/s)
- Resulting tendency value
- Local dn0 and dz values
- Verification calculation

## Expected Values (Based on RAMSIN Configuration)

### Configuration:
- BTHP = 500 W/m²
- Grid: 200x200x108 points
- Spacing: deltax=500m, deltaz=25m (stretched)
- Heating region: i=90-110, j=90-110 (21x21 points)
- Vertical: IBDZK2=15 (e-folding height)
- Timing: ramp 0-300s, plateau 300-1740s, ramp down 1740-1800s

### Expected Spatial Parameters:
- bubradx = bubrady = (110-90)*500*0.5 = 5000 m
- At grid center (100,100): r_horiz = 0, horiz_gauss = 1.0
- At edge (90 or 110): r_horiz = 1, horiz_gauss = exp(-1) ≈ 0.37

### Expected Physical Values:
For k=2 (lowest model level), center of heating region, at t=300s:

- temporal_factor = 1.0 (fully ramped up)
- horiz_gauss ≈ 1.0 (at center)
- vert_decay ≈ exp(-z/atten_length) ≈ 0.9-1.0 (near surface)
- heating_wm2 ≈ 500 W/m²

With typical atmospheric values:
- dn0 ≈ 1.2 kg/m³
- dz ≈ 25 m (first layer)
- cp = 1004 J/(kg·K)

Expected heating_rate:
```
heating_rate = 500 / (1.2 × 25 × 1004)
            = 500 / 30120
            ≈ 0.0166 K/s
```

Over timestep (dt=1s): 0.0166 K per step
Over 300s: ~5 K total heating

## Potential Issues to Check

### 1. **Very Small Values**
If heating_rate << 0.01 K/s at center:
- Check dn0: should be ~1-1.2 kg/m³ at surface
- Check dz: should be ~25 m for first layer
- Check heating_wm2: should be close to BTHP * temporal_factor near center

### 2. **Wrong Location**
If max heating not at expected location:
- Check bubctrx, bubctry calculation
- Should be near 0 for centered domain
- Max should be near i=100, j=100, k=2-10

### 3. **Wrong Time Evolution**
- At t=1s: temporal_factor = 1/300 ≈ 0.003
- At t=300s: temporal_factor = 1.0
- At t=1200s: temporal_factor = 1.0
- At t=1740s: temporal_factor = 1.0 (start decay)

### 4. **Vertical Profile Issues**
- Check atten_length value
- Should be height at level IBDZK2=15
- For deltaz=25m with stretching, this might be ~500-1000m
- vert_decay should decrease with height

### 5. **Array Indexing**
If getting segfaults or wrong values:
- Check (i-ia+1, j-ja+1) indexing
- Verify dn0, rtgt arrays have correct dimensions

### 6. **Coordinate System**
- XMN, YMN should give grid cell face coordinates
- Center of cell should be average of faces
- Check if domain is centered correctly

## Next Steps

1. Run the simulation and capture output
2. Look for debug messages from volumetric_heating
3. Check if values match expectations
4. If heating_rate is too small, check intermediate values
5. If no output appears, check if subroutine is being called

## Quick Diagnostic Commands

After run completes, grep for debug output:
```bash
grep "VOLUMETRIC HEATING" <output_file>
grep "Max heating_wm2" <output_file>
```

## Suspected Issues

Based on "very small" temperature perturbations, likely causes:
1. Tendency integration issue (heating_rate correct but not integrating properly)
2. Unit conversion error (less likely - formula looks correct)
3. Spatial distribution too spread out (check bubradx calculation)
4. Time stepping issue (dt=1s might be integrating differently than expected)
5. Tendency vs. actual field confusion (are we modifying the right variable?)

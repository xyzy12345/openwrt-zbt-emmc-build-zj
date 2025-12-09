# Build Error Analysis

## Latest Error - Workflow Run #20040943331

**Workflow Run:** https://github.com/xyzy12345/openwrt-zbt-emmc-build-zj/actions/runs/20040943331

**Status:** ❌ Failed (Missing Build Function)

**Job:** build (Step 8: "Build OpenWrt")

### Error Summary

OpenWrt build failed with a missing build function error:

```
Makefile:49: *** Missing Build/sysupgrade-emmc.  Stop.
```

### Root Cause

The device definition for `zbtlink_z8102ax-emmc` in `target/linux/mediatek/image/filogic.mk` referenced a build function `sysupgrade-emmc` on line 154, but this function was never defined.

```makefile
IMAGE/sysupgrade.bin := sysupgrade-emmc | append-metadata
```

The OpenWrt build system requires that all build functions referenced in device definitions must be defined. The `sysupgrade-emmc` function is a custom function needed to create the sysupgrade firmware image for eMMC-based devices.

### Solution Applied

Added the missing `Build/sysupgrade-emmc` function definition in `target/linux/mediatek/image/filogic.mk`:

```makefile
define Build/sysupgrade-emmc
	$(call Build/mt798x-gpt,emmc)
	$(call Build/pad-to,64M)
	$(call Build/append-kernel)
	$(call Build/append-rootfs)
	$(call Build/check-size)
endef
```

This function:
1. Creates a GPT partition table suitable for eMMC devices using `Build/mt798x-gpt` with the `emmc` parameter
2. Pads the image to 64M to match the partition layout defined in `mt798x-gpt`
3. Appends the kernel image
4. Appends the root filesystem
5. Checks that the final image size is within limits

### Changes Made

**File Modified:** `target/linux/mediatek/image/filogic.mk`

**Change Type:** Add missing build function definition

**Lines Added:** 142-148 (8 lines)

**Commit:** 4420be1 - "Add Build/sysupgrade-emmc function for eMMC device support"

### Expected Outcome

✅ The build system can now find the `Build/sysupgrade-emmc` function  
✅ OpenWrt build should proceed to create the sysupgrade image  
✅ The firmware image will have proper GPT partitioning for eMMC devices  

---

---

## Workflow Run #20038869131

**Workflow Run:** https://github.com/xyzy12345/openwrt-zbt-emmc-build-zj/actions/runs/20038869131

**Status:** ❌ Failed (Duplicate Label Error)

**Job:** build (Step 8: "Build OpenWrt")

### Error Summary

Device Tree Source (DTS) compilation failed due to a duplicate label definition:

```
ERROR (duplicate_label): /soc/efuse@11f20000/calib@8dc: Duplicate label 'phy_calibration' on /soc/efuse@11f20000/calib@8dc and /soc/efuse@11f20000/phy-calib@8dc
```

### Root Cause

The `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts` file defined a label `phy_calibration` at line 368:

```dts
&efuse {
    phy_calibration: calib@8dc {
        reg = <0x8dc 0x10>;
    };
    // ... other nodes
}
```

However, the parent `mt7981.dtsi` file (from OpenWrt source) already defines a `phy-calib@8dc` node with the `phy_calibration` label. Device Tree labels must be unique across the entire device tree, so this caused a duplicate label error.

### Solution Applied

Removed the duplicate `phy_calibration: calib@8dc` definition from the `&efuse` block in both:
- `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts`
- `custom-configs/dts/mt7981b-zbt-z8102ax-emmc.dts`

The DTS file now relies on the `phy_calibration` label provided by the parent `mt7981.dtsi`, which is the correct approach. The reference at line 164 (`nvmem-cells = <&phy_calibration>;`) will correctly resolve to the parent's definition.

### Changes Made

**Files Modified:**
1. `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts` - Removed lines 368-370
2. `custom-configs/dts/mt7981b-zbt-z8102ax-emmc.dts` - Removed lines 368-370

**Change Type:** Remove duplicate definition (no functional change)

---

## Previous Error - Workflow Run #20036959834

**Workflow Run:** https://github.com/xyzy12345/openwrt-zbt-emmc-build-zj/actions/runs/20036959834

**Status:** ❌ Failed (Resolved)

**Job:** build (Step 8: "Build OpenWrt")

## Root Cause

Device Tree Source (DTS) compilation error in `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts`

### Error Message
```
Error: ../dts/mt7981b-zbt-z8102ax-emmc.dts:299.2-320.26 
Properties must precede subnodes
FATAL ERROR: Unable to parse input tree
```

### Issue Description

The Device Tree Compiler (DTC) failed because the DTS file violated a fundamental syntax rule:

**In DTS files, all property definitions must come before any child node (subnode) definitions within a node.**

### Problematic Code Structure (Before Fix)

In the `&pio` node (starting at line 284), the structure was:

```dts
&pio {
    mmc0_pins_default: mmc0-pins-default {    // ❌ Child node defined first
        mux {
            function = "flash";
            groups = "emmc_45";
        };
    };

    mmc0_pins_uhs: mmc0-pins-uhs {            // ❌ Another child node
        mux {
            function = "flash";
            groups = "emmc_45";
        };
    };

    gpio-line-names =                          // ❌ Property defined AFTER child nodes
        "mesh",    /* GPIO0 */
        "reset",   /* GPIO1 */
        // ... (more GPIO names)
        ;
}
```

## Solution Applied

Reordered the node contents to comply with DTS syntax requirements:

### Fixed Code Structure (After Fix)

```dts
&pio {
    gpio-line-names =                          // ✅ Property defined FIRST
        "mesh",    /* GPIO0 */
        "reset",   /* GPIO1 */
        // ... (more GPIO names)
        ;

    mmc0_pins_default: mmc0-pins-default {    // ✅ Child nodes come AFTER properties
        mux {
            function = "flash";
            groups = "emmc_45";
        };
    };

    mmc0_pins_uhs: mmc0-pins-uhs {            // ✅ Second child node
        mux {
            function = "flash";
            groups = "emmc_45";
        };
    };
}
```

## Changes Made

**File Modified:** `target/linux/mediatek/dts/mt7981b-zbt-z8102ax-emmc.dts`

**Change Type:** Code reordering (no logic changes)

**Lines Affected:** 284-320

**Commit:** ebc1e4d - "Fix DTS syntax error: Move gpio-line-names before child nodes"

## DTS Syntax Rules Reference

### Correct Node Structure
```dts
node_name {
    /* Properties always come first */
    property1 = <value>;
    property2 = "string";
    property3;
    
    /* Child nodes always come after properties */
    child_node_1 {
        // child properties and subnodes
    };
    
    child_node_2 {
        // child properties and subnodes
    };
};
```

### Common Property Types
1. `#address-cells`, `#size-cells` - Define address/size format
2. `compatible` - Device compatibility string
3. `reg` - Register address/size
4. `status` - Node status ("okay", "disabled", etc.)
5. `gpio-line-names` - GPIO pin naming
6. Custom properties specific to the device/driver

## Verification

After applying this fix, the DTS file should compile successfully. The OpenWrt build process uses the Device Tree Compiler (DTC) which will:

1. Parse the DTS file
2. Validate syntax according to DTS specification
3. Generate a Device Tree Blob (DTB) binary
4. Include the DTB in the firmware image

## Expected Outcome

✅ The build should now proceed past the DTS compilation stage
✅ No functional changes to the device behavior (only syntax correction)
✅ All GPIO definitions and pin configurations remain unchanged

## References

- [Device Tree Specification](https://www.devicetree.org/)
- [Linux Kernel Device Tree Documentation](https://www.kernel.org/doc/Documentation/devicetree/)
- [OpenWrt DTS Guide](https://openwrt.org/docs/guide-developer/defining-firmware-partitions)

# Arm MMU implementation

A clean and maintainable Arm MMU configuration implementation. This project allows for a simple configuration of page tables in all three granules as well as table entry attributes, important configuration registers(tcr, mair).
I wrote this implementation for [this](https://github.com/luickk/MinimalRoboticsPlatform) project, but since it offers such a great standalone value to all bare matel projects, I created this repo.

This project is not a simple solution and basic understanding of the mmu is required. Things this project does not do for you includes tcr/ mair reg configuration as well as virtual address start calc which differ per granule and configuration.

## Supports

Granules:

- 4k Sectioned
- 4k
- 16k
- 64k

## Demo

### Simple Section Setup

```zig
// creating PageTable with 0x40000000 in size, Fourk granule and 0x20000000 as page table array addr start as well as 0 load mem addr(lma)
// lma: is only required when the address space the code is currently executed already has an offset to the actual physical offset
var ttbr1_write = (try mmu.PageTable(0x40000000, Granule.Fourk).init(0x20000000, 0x0);

// creating virtual address space for kernel
const kernel_space_mapping = mmu.Mapping{
	// we could also only map parts of the available memory (0x40000000) and map the rest differently
    .mem_size = 0x40000000,
    // the addresss where the descriptors point to (and start increasing from there)
    .pointing_addr_start = 0x40000000,
    // defines where the virtual address starts (modulates the descriptor placement)
    // if virt_addr_start was 0x500 and pointing_addr_start 0x100 a cpu mem access to 0x0 
    // would result in a mmu access fault but an access to 0x500 would actually access 0x100
    .virt_addr_start = 0,
    // Has to be similar to the above
    .granule = Granule.Fourk,
    .addr_space = .ttbr1,
    // last descriptors (block) level flags
    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .attrIndex = .mair0 },
    // defines (only) first level flags
    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write },
};

// writes the mapping to the PageTable
try ttbr1_write.mapMem(kernel_space_mapping);
```

### Tcr/ Mair register config

All possible configuration parameters can be found in `mmu.zig`.
```zig
// tnsz of 25 has a min start address of 0xFFFFFF8000000000 in a 4k granule config (which is indicated by tgn=0)
proc.TcrReg.setTcrEl(.el1, (proc.TcrReg{ .t0sz = 25, .t1sz = 25, .tg0 = 0, .tg1 = 0 }).asInt());
```

```zig
proc.MairReg.setMairEl(.el1, (proc.MairReg{ .attr0 = 0xFF, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());
```

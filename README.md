# Arm MMU implementation

A clean and maintainable Arm MMU configuration implementation. This project allows for a simple configuration of page tables in all three granules as well as table entry attributes, important configuration registers(tcr, mair).
I wrote this implementation for [this](https://github.com/luickk/MinimalRoboticsPlatform) project, but since it offers such a great standalone value to all bare matel projects, I created this repo.

## Demo

### Simple Section Setup

```zig
// defining section mapping.
// 1gb in size, with virt and physical address being the same -> identity mapped
var bootloader_mapping = mmu.Mapping{ .mem_size = 0x40000000, .virt_start_addr = 0, .phys_addr = 0 };

// _ttbr0_dir defines the address to which the section is writte
// TableEntryAttr defines the first translation level configuration (mmu.zig for all possible configurations)
try mmu.createSection(_ttbr0_dir, bootloader_mapping, mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block });
```

### Properly Mapped Page Dir

```zig
const user_mapping = mmu.Mapping{ .mem_size = 0x40000000, .virt_start_addr = 0, .phys_addr = 0x40000000 };
// initing PageDir with 4k granule at address _u_ttbr0_dir
var ttbr0 = try (try mmu.PageDir(user_mapping, mmu.Granule.Fourk)).init(_u_ttbr0_dir);
try ttbr0.mapMem();
```

### Tcr/ Mair register config

All possible configuration parameters can be found in `mmu.zig`.
```zig
var tcr = (mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 2 }).asInt();
```

```zig
var tcr = (mmu.MairReg{ .attr1 = 4, .attr2 = 4 }).asInt();
```

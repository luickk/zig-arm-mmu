pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

pub const Mapping = struct { mem_size: usize, virt_start_addr: usize, phys_addr: usize };

const GranuleParams = struct {
    page_size: usize,
    lvls_required: TransLvl,
};

pub const Granule = struct {
    pub const Fourk: GranuleParams = .{ .page_size = 4096, .lvls_required = .third_lvl };
    pub const Sixteenk: GranuleParams = .{ .page_size = 16384, .lvls_required = .third_lvl };
    pub const Sixtyfourk: GranuleParams = .{ .page_size = 65536, .lvls_required = .second_lvl };
};

const vaStart: usize = 0xffff000000000000;

// In addition to an output address, a translation table entry that refers to a page or region of memory
// includes fields that define properties of the target memory region. These fields can be classified as
// address map control, access control, and region attribute fields.
pub const TableEntryAttr = packed struct {
    // block indicates next trans lvl (or physical for sections) and page the last trans lvl (with physical addr)
    pub const DescType = enum(u1) { block = 0, page = 1 };
    // redirects read from mem tables to mairx reg
    pub const AttrIndex = enum(u3) { mair0 = 0, mair1 = 1 };
    pub const Sharability = enum(u2) { non_sharable = 0, unpredictable = 1, outer_sharable = 2, innner_sharable = 3 };

    // for Non-secure stage 1 of the EL1&0 translation regime
    pub const Stage1AccessPerm = enum(u2) { only_el1_read_write = 0, read_write = 1, only_el1_read_only = 2, read_only = 3 };
    // for Non-secure EL1&0 stage 2 translation regime
    pub const Stage2AccessPerm = enum(u2) { none = 0, read_only = 1, write_only = 2, read_write = 3 };
    // for secure EL2&3 translation regime
    pub const SecureAccessPerm = enum(u2) { read_write = 0, read_only = 3 };

    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_1_vmsav8-64_translation_table_descriptor_formats.html
    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_2_armv8_translation_table_level_3_descriptor_formats.html
    // identifies whether the descriptor is valid, and is 1 for a valid descriptor.
    valid: bool = true,
    // identifies the descriptor type, and is encoded as:
    descType: DescType = .block,

    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_3_memory_attribute_fields_in_the_vmsav8-64_translation_table_formats_descriptors.html
    attrIndex: AttrIndex = .mair1,
    // For memory accesses from Secure state, specifies whether the output address is in the Secure or Non-secure address map
    ns: bool = false,
    // depends on translation level (Stage2AccessPerm, Stage1AccessPerm, SecureAccessPerm)
    accessPerm: Stage1AccessPerm = .read_only,
    sharableAttr: Sharability = .non_sharable,

    // The access flag indicates when a page or section of memory is accessed for the first time since the
    // Access flag in the corresponding translation table descriptor was set to 0.
    accessFlag: bool = true,
    // the not global bit. Determines whether the TLB entry applies to all ASID values, or only to the current ASID value
    notGlobal: bool = false,

    _padding: u39 = 0,

    // indicating that the translation table entry is one of a contiguous set or entries, that might be cached in a single TLB entry
    contiguous: bool = false,
    // priviledeg execute-never bit. Determines whether the region is executable at EL1
    pxn: bool = false,
    // execute-never bit. Determines whether the region is executable
    uxn: bool = false,

    _padding2: u10 = 0,

    pub fn asInt(self: TableEntryAttr) usize {
        return @bitCast(u64, self);
    }
};

pub const MairReg = packed struct {
    attr0: u8 = 0,
    attr1: u8 = 0,
    attr2: u8 = 0,
    attr3: u8 = 0,
    attr4: u8 = 0,
    attr5: u8 = 0,
    attr6: u8 = 0,
    attr7: u8 = 0,

    pub fn asInt(self: MairReg) usize {
        return @bitCast(u64, self);
    }
};
pub const TcrReg = packed struct {
    t0sz: u6 = 0,
    reserved0: bool = false,
    epd0: bool = false,
    irgno0: u2 = 0,
    orgn0: u2 = 0,
    sh0: u2 = 0,
    tg0: u2 = 0,
    t1sz: u6 = 0,
    a1: bool = false,
    epd1: bool = false,
    irgn1: u2 = 0,
    orgn1: u2 = 0,
    sh1: u2 = 0,
    tg1: u2 = 0,
    ips: u3 = 0,
    reserved1: bool = false,
    as: bool = false,
    tbi0: bool = false,
    tbi1: bool = false,
    ha: bool = false,
    hd: bool = false,
    hpd0: bool = false,
    hpd1: bool = false,
    hwu059: bool = false,
    hwu060: bool = false,
    hwu061: bool = false,
    hwu062: bool = false,
    hwu159: bool = false,
    hwu160: bool = false,
    hwu161: bool = false,
    hwu162: bool = false,
    tbid0: bool = false,
    tbid1: bool = false,
    nfd0: bool = false,
    nfd1: bool = false,
    e0pd0: bool = false,
    e0pd1: bool = false,
    tcma0: bool = false,
    tcma1: bool = false,
    ds: bool = false,
    reserved2: u4 = 0,

    pub fn asInt(self: TcrReg) usize {
        return @bitCast(u64, self);
    }
};

pub fn PageDir(mapping: Mapping, granule: GranuleParams) type {
    const page_size = granule.page_size;
    const table_len = page_size / @sizeOf(usize);
    const max_lvl = granule.lvls_required;
    return struct {
        const Self = @This();
        page_size: usize,
        table_len: usize,

        mapping: Mapping,
        max_lvl: TransLvl,
        map_pg_dir: []volatile [table_len]usize,

        const Error = error{MemSizeTooBig};

        pub fn init(base_addr: usize) !Self {
            var map_pg_dir: []volatile [table_len]usize = undefined;
            map_pg_dir.ptr = @intToPtr([*]volatile [table_len]usize, base_addr);
            map_pg_dir.len = table_len * page_size;
            return Self{
                // sizes
                .page_size = page_size,
                .table_len = table_len,

                .max_lvl = max_lvl,
                .mapping = mapping,
                .map_pg_dir = map_pg_dir,
            };
        }

        fn calcTransLvlEntrySize(self: *Self, lvl: TransLvl) usize {
            return std.math.pow(usize, self.table_len, @enumToInt(self.max_lvl) - @enumToInt(lvl)) * self.page_size;
        }

        // 1*512*512*4096
        // 512^(i-1)*4096
        pub fn mapMem(self: *Self) !void {
            // calc amounts of tables required per lvl
            var table_entries = [_]usize{0} ** 3;
            var curr_lvl: usize = 0;
            const lvl_1 = (TableEntryAttr{ .accessPerm = .read_write, .descType = .block }).asInt();

            while (curr_lvl <= @enumToInt(self.max_lvl)) : (curr_lvl += 1) {
                table_entries[curr_lvl] = try std.math.divCeil(usize, self.mapping.mem_size, self.calcTransLvlEntrySize(@intToEnum(TransLvl, curr_lvl)));
            }

            curr_lvl = 0;
            var phys_count = self.mapping.phys_addr | (TableEntryAttr{ .accessPerm = .read_write, .descType = .page }).asInt();
            var pg_dir_offset: usize = 0;
            while (curr_lvl <= @enumToInt(self.max_lvl)) : (curr_lvl += 1) {
                var req_table = (try std.math.divCeil(usize, table_entries[curr_lvl], self.table_len));
                var req_entry: usize = table_entries[curr_lvl];
                var curr_entry: usize = 0;
                var curr_table: usize = 0;
                while (curr_table < req_table) : (curr_table += 1) {
                    curr_entry = 0;
                    if (req_entry > self.table_len)
                        req_entry -= self.table_len;
                    while (curr_entry <= self.table_len) : (curr_entry += 1) {
                        // last lvl translation links to physical mem
                        if (curr_lvl == @enumToInt(self.max_lvl)) {
                            self.map_pg_dir[pg_dir_offset + curr_table][curr_entry] = phys_count;
                            phys_count += self.page_size;
                            // trans layer before link to next tables
                        } else {
                            self.map_pg_dir[pg_dir_offset + curr_table][curr_entry] = @ptrToInt(&self.map_pg_dir[pg_dir_offset + req_table + curr_entry]);
                            if (curr_lvl == @enumToInt(TransLvl.first_lvl))
                                self.map_pg_dir[pg_dir_offset + curr_table][curr_entry] |= lvl_1;
                        }
                        if (req_entry < self.table_len)
                            break;
                    }
                }
                pg_dir_offset += req_table;
            }
            // kprint("base address: {*} \n", .{self.map_pg_dir.ptr});
            // kprint("1 lvl (1 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[0][0], self.map_pg_dir[0][0] });
            // kprint("------- \n", .{});
            // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][0], self.map_pg_dir[1][0] });
            // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][1], self.map_pg_dir[1][1] });
            // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][2], self.map_pg_dir[1][2] });
            // kprint("------- \n", .{});
            // kprint("3 lvl (3 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[2][0], self.map_pg_dir[2][0] });
            // kprint("3 lvl (4 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[3][0], self.map_pg_dir[3][0] });
            // kprint("3 lvl (5 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[4][0], self.map_pg_dir[4][0] });
        }
    };
}

// populates a Page Table with physical adresses aka. sections or pages
pub fn createSection(pg_dir_addr: usize, mapping: Mapping, flags: TableEntryAttr) !void {
    const section_size = 2097152;

    var pg_dir = @intToPtr([*]volatile usize, pg_dir_addr);

    var phys_count = mapping.phys_addr | flags.asInt();
    // phys_count >>= shift;
    // phys_count |= phys_shifted;

    var i: usize = mapping.virt_start_addr;
    i = toUnsecure(usize, i);
    i = try std.math.divCeil(usize, i, section_size);

    var i_max: usize = mapping.virt_start_addr + mapping.mem_size;
    i_max = toUnsecure(usize, i_max) - toUnsecure(usize, mapping.virt_start_addr);
    i_max = try std.math.divCeil(usize, i_max, section_size);

    while (i <= i_max) : (i += 1) {
        pg_dir[i] = phys_count;
        phys_count += section_size;
    }
}

pub fn zeroPgDir(pg_dir: []volatile usize) void {
    for (pg_dir) |*e| {
        e.* = 0x0;
    }
}

pub inline fn toSecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) | vaStart);
        },
        .Int => {
            return inp | vaStart;
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}

pub inline fn toUnsecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) & ~(vaStart));
        },
        .Int => {
            return inp & ~(vaStart);
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}
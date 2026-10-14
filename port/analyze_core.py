#!/usr/bin/env python3
"""
Stand-alone AArch64 Linux ELF Core Dump Analyzer for PortMaster / RK3326.
Extracts signal, registers, mapped libraries (NT_FILE), and stack backtrace
without requiring GDB or binutils strings.
"""
import sys, os, struct

def analyze(core_path):
    if not os.path.isfile(core_path):
        print(f"Core file not found: {core_path}")
        return

    try:
        f = open(core_path, "rb")
    except Exception as e:
        print(f"Failed to open core file: {e}")
        return

    magic = f.read(4)
    if magic != b"\x7fELF":
        print("Invalid ELF magic header.")
        f.close()
        return

    ei_class, ei_data, ei_version = struct.unpack("BBB", f.read(3))
    if ei_class != 2:
        print("Not a 64-bit ELF.")
        f.close()
        return

    f.seek(18)
    e_machine = struct.unpack("<H", f.read(2))[0]
    # 0xB7 (183) is AArch64
    arch = "AArch64" if e_machine == 183 else f"Unknown ({e_machine})"

    f.seek(32)
    e_phoff = struct.unpack("<Q", f.read(8))[0]
    f.seek(54)
    e_phentsize, e_phnum = struct.unpack("<HH", f.read(4))

    notes = []
    load_segments = []

    for i in range(e_phnum):
        f.seek(e_phoff + i * e_phentsize)
        hdr = f.read(e_phentsize)
        if len(hdr) < 56:
            continue
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack("<IIQQQQQQ", hdr[:56])
        if p_type == 4: # PT_NOTE
            notes.append((p_offset, p_filesz))
        elif p_type == 1: # PT_LOAD
            load_segments.append((p_vaddr, p_vaddr + p_memsz, p_offset, p_filesz))

    regs = {}
    sig = None
    mapped_files = []

    for n_off, n_sz in notes:
        f.seek(n_off)
        end = n_off + n_sz
        while f.tell() < end:
            hdr_bytes = f.read(12)
            if len(hdr_bytes) < 12:
                break
            namesz, descsz, n_type = struct.unpack("<III", hdr_bytes)
            name_padded = ((namesz + 3) // 4) * 4
            desc_padded = ((descsz + 3) // 4) * 4

            name = f.read(namesz).rstrip(b"\x00").decode("latin-1", "ignore")
            f.seek(name_padded - namesz, 1)

            desc = f.read(descsz)
            f.seek(desc_padded - descsz, 1)

            if n_type == 1 and descsz >= 112: # NT_PRSTATUS
                # struct elf_prstatus on aarch64
                # offset 12: pr_cursig (2 bytes)
                pr_cursig = struct.unpack("<H", desc[12:14])[0]
                sig = pr_cursig
                # Registers are at the end: struct user_pt_regs is 272 bytes (34 * 8)
                if descsz >= 272:
                    reg_data = desc[-272:]
                    for r in range(31):
                        regs[f"x{r}"] = struct.unpack("<Q", reg_data[r*8:(r+1)*8])[0]
                    regs["sp"] = struct.unpack("<Q", reg_data[248:256])[0]
                    regs["pc"] = struct.unpack("<Q", reg_data[256:264])[0]
                    regs["pstate"] = struct.unpack("<Q", reg_data[264:272])[0]

            elif n_type == 0x46494c45 and descsz >= 16: # NT_FILE
                count, page_size = struct.unpack("<QQ", desc[:16])
                entry_sz = 24
                if descsz >= 16 + count * entry_sz:
                    entries = []
                    for ci in range(count):
                        s_addr, e_addr, pgoff = struct.unpack("<QQQ", desc[16 + ci*entry_sz : 16 + (ci+1)*entry_sz])
                        entries.append((s_addr, e_addr, pgoff))
                    str_pool = desc[16 + count*entry_sz:]
                    f_names = str_pool.split(b"\x00")
                    for ci in range(min(count, len(f_names))):
                        fn = f_names[ci].decode("latin-1", "ignore")
                        if fn:
                            s_addr, e_addr, pgoff = entries[ci]
                            mapped_files.append((s_addr, e_addr, pgoff, fn))

    # Helper to resolve an address to a file and offset
    def resolve_addr(addr):
        for s_addr, e_addr, pgoff, fn in mapped_files:
            if s_addr <= addr < e_addr:
                offset = (addr - s_addr) + (pgoff * 4096)
                base = os.path.basename(fn)
                return f"{base} + 0x{offset:x} ({fn})"
        return None

    # Helper to read memory from PT_LOAD segments
    def read_mem(vaddr, size):
        for s_v, e_v, p_off, p_fsz in load_segments:
            if s_v <= vaddr < e_v:
                rel = vaddr - s_v
                read_sz = min(size, p_fsz - rel)
                if read_sz <= 0:
                    return b""
                f.seek(p_off + rel)
                return f.read(read_sz)
        return b""

    print(f"=== Core Dump Analysis ({arch}) ===")
    if sig:
        signames = {4: "SIGILL", 6: "SIGABRT", 7: "SIGBUS", 8: "SIGFPE", 11: "SIGSEGV"}
        print(f"Fatal Signal: {sig} ({signames.get(sig, 'UNKNOWN')})")

    if "pc" in regs:
        pc_sym = resolve_addr(regs['pc']) or "unknown memory"
        lr_sym = resolve_addr(regs.get('x30', 0)) or "unknown memory"
        print(f"Faulting PC : 0x{regs['pc']:016x} -> {pc_sym}")
        print(f"Link Reg LR : 0x{regs.get('x30', 0):016x} -> {lr_sym}")
        print(f"Stack Ptr SP: 0x{regs.get('sp', 0):016x}")
        print(f"Fault Arg x0: 0x{regs.get('x0', 0):016x}")

        print("\n--- Key Registers ---")
        for r in range(0, 31, 2):
            r1 = f"x{r}: 0x{regs.get(f'x{r}', 0):016x}"
            r2 = f"x{r+1}: 0x{regs.get(f'x{r+1}', 0):016x}" if (r+1) < 31 else ""
            print(f"  {r1:<26} {r2}")

        # Scan stack for backtrace
        sp = regs.get("sp", 0)
        if sp != 0:
            stack_bytes = read_mem(sp, 2048)
            print("\n--- Stack Backtrace (Resolved Symbols) ---")
            frame_idx = 0
            print(f"#{frame_idx:<2} 0x{regs['pc']:016x} in {pc_sym}")
            frame_idx += 1
            if regs.get('x30', 0) != 0 and regs.get('x30', 0) != regs['pc']:
                print(f"#{frame_idx:<2} 0x{regs['x30']:016x} in {lr_sym}")
                frame_idx += 1

            seen_addrs = set([regs['pc'], regs.get('x30', 0)])
            for off in range(0, len(stack_bytes) - 7, 8):
                val = struct.unpack("<Q", stack_bytes[off:off+8])[0]
                if val not in seen_addrs and val > 0x10000:
                    sym = resolve_addr(val)
                    if sym and not sym.startswith("[stack"):
                        print(f"#{frame_idx:<2} 0x{val:016x} in {sym}")
                        seen_addrs.add(val)
                        frame_idx += 1
                        if frame_idx >= 25:
                            break

    print("\n--- Loaded Shared Libraries (Memory Map) ---")
    unique_libs = {}
    for s_addr, e_addr, pgoff, fn in mapped_files:
        if fn not in unique_libs or s_addr < unique_libs[fn][0]:
            unique_libs[fn] = (s_addr, e_addr)
    for fn, (s_addr, e_addr) in sorted(unique_libs.items(), key=lambda x: x[1][0]):
        print(f"  0x{s_addr:012x}-0x{e_addr:012x} {fn}")

    f.close()

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "/tmp/core"
    analyze(target)

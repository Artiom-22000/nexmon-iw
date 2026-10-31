/*
 * nexcap - set a CAP_NET_ADMIN (effective+permitted) file capability on files
 *          by writing the security.capability xattr directly (vfs cap v2).
 *          Freestanding aarch64: raw syscalls, no libc, ~4 KB static binary.
 *
 * The 20-byte xattr layout matches what libcap produces on Linux
 * (verified against a system `ping` binary with cap_net_raw+ep):
 *
 *   magic_etc         = 0x02000001  (VFS_CAP_REVISION_2 | VFS_CAP_FLAGS_EFFECTIVE)
 *   data[0].permitted = 0x00001000  (CAP_NET_ADMIN)
 *   data[0].inherited = 0
 *   data[1].permitted = 0
 *   data[1].inherited = 0
 *   (all u32 stored little-endian)
 *
 * Usage: nexcap FILE...
 * Exit: 0 = all ok, 1 = some failed, 2 = usage error.
 * Requires the caller to have CAP_SETFCAP (e.g. Magisk post-fs-data/service
 * script context) and a filesystem that supports xattrs (not mounted nosuid).
 */

#define NULL ((void *)0)

typedef unsigned long u64;
typedef long          s64;

static const char CAP_XATTR[]   = "security.capability";
static unsigned char CAP_BYTES_MUT[20] = {
    0x01, 0x00, 0x00, 0x02,   /* magic_etc: VFS_CAP_REVISION_2 | EFFECTIVE */
    0x00, 0x10, 0x00, 0x00,   /* permitted lo: CAP_NET_ADMIN               */
    0x00, 0x00, 0x00, 0x00,   /* permitted hi                              */
    0x00, 0x00, 0x00, 0x00,   /* inheritable lo                            */
    0x00, 0x00, 0x00, 0x00,   /* inheritable hi                            */
};

/* asm-generic syscall numbers (arm64): setxattr=5, write=64, exit_group=94 */
#define __NR_setxattr   5
#define __NR_write     64
#define __NR_exit_group 94

static s64 sys_syscall5(s64 nr, s64 a, s64 b, s64 c, s64 d, s64 e)
{
    register s64 x0 asm("x0") = a;
    register s64 x1 asm("x1") = b;
    register s64 x2 asm("x2") = c;
    register s64 x3 asm("x3") = d;
    register s64 x4 asm("x4") = e;
    register s64 x8 asm("x8") = nr;
    asm volatile ("svc 0"
                  : "+r"(x0)
                  : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x8)
                  : "memory");
    return x0;
}

static s64 sys_write(s64 fd, const void *buf, u64 len)
{
    if (len == 0)
        return 0;
    return sys_syscall5(__NR_write, fd, (s64)buf, (s64)len, 0, 0);
}

static u64 slen(const char *s)
{
    u64 n = 0;
    while (s[n])
        n++;
    return n;
}

static void wstr(s64 fd, const char *s)
{
    sys_write(fd, s, slen(s));
}

static void wnum(s64 fd, u64 v, unsigned base)
{
    char tmp[24];
    int  i = 0;

    if (v == 0) {
        sys_write(fd, "0", 1);
        return;
    }
    while (v > 0 && i < (int)sizeof(tmp)) {
        u64 d = v % base;
        tmp[i++] = (char)(d < 10 ? '0' + (int)d : 'a' + (int)d - 10);
        v /= base;
    }
    while (i > 0)
        sys_write(fd, &tmp[--i], 1);
}

static void mkerr(s64 e, char *buf)
{
    const char *m;
    int i = 0, j = 0;

    switch (e) {
    case 1:      m = "EPERM";      break;
    case 2:      m = "ENOENT";     break;
    case 13:     m = "EACCES";     break;
    case 22:     m = "EINVAL";     break;
    case 38:     m = "ENOSYS";     break;
    case 40:     m = "ELOOP";      break;
    case 95:     m = "EOPNOTSUPP"; break;
    case 61:     m = "ENODATA";    break;
    default:     m = "E?";
    }
    buf[i++] = '(';
    while (m[j])
        buf[i++] = m[j++];
    buf[i++] = ')';
    buf[i] = 0;
}

__attribute__((used))
void cmain(u64 *sp)
{
    u64    argc = sp[0];
    char **argv = (char **)(sp + 1);
    u64    ret  = 0;
    char   ebuf[40];

    /* nexcap [-m <hexmask>] FILE...
     * default mask: CAP_NET_ADMIN (0x1000); -m replaces the permitted-lo
     * half of the xattr, e.g. -m 3000 = NET_ADMIN|NET_RAW for the air *
     * tools. The xattr stays vfs cap v2 | EFFECTIVE. */
    u64 first = 1;
    if (argc >= 3 && argv[1][0] == '-' && argv[1][1] == 'm') {
        u64 mask = 0, pos = 0;
        const char *h = argv[2];
        while (h[pos]) {
            u64 d = 999;
            u64 c = (u64)h[pos];
            if (c >= '0' && c <= '9') d = c - '0';
            if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
            if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
            if (d == 999) { mask = (u64)-1; break; }
            mask = (mask << 4) | d;
            pos++;
        }
        if (mask == (u64)-1 || mask > 0xffff) {
            wstr(2, "nexcap: bad -m mask\n");
            sys_syscall5(__NR_exit_group, 2, 0, 0, 0, 0);
        }
        CAP_BYTES_MUT[4] = (unsigned char)(mask & 0xff);
        CAP_BYTES_MUT[5] = (unsigned char)((mask >> 8) & 0xff);
        first = 3;
    }

    if (first >= argc) {
        wstr(2, "usage: nexcap [-m hexmask] FILE...\n");
        sys_syscall5(__NR_exit_group, 2, 0, 0, 0, 0);
    }

    for (u64 i = first; i < argc; i++) {
        s64 rc = sys_syscall5(__NR_setxattr, (s64)argv[i],
                              (s64)CAP_XATTR, (s64)CAP_BYTES_MUT,
                              (s64)sizeof(CAP_BYTES_MUT), 0);
        if (rc == 0) {
            wstr(2, "nexcap: ");
            wstr(2, argv[i]);
            wstr(2, ": set\n");
        } else {
            wstr(2, "nexcap: ");
            wstr(2, argv[i]);
            wstr(2, ": failed rc=");
            wnum(2, (u64)(rc * -1), 10);
            mkerr(rc * -1, ebuf);
            wstr(2, " ");
            wstr(2, ebuf);
            sys_write(2, "\n", 1);
            ret = 1;
        }
    }

    sys_syscall5(__NR_exit_group, (s64)ret, 0, 0, 0, 0);
}

/* entry trampoline: arm64 _start receives the stack pointer; argc sits at [sp] */
asm(
    ".text\n"
    ".global _start\n"
    "_start:\n"
    "    mov x0, sp\n"
    "    bl  cmain\n"
    /* cmain must not return, but be safe: */
    "    mov x8, 94\n"
    "    mov x0, 99\n"
    "    svc 0\n"
);

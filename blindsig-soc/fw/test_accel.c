// test_accel.c — Integration test: PicoRV32 → blind signature accelerator
//
// Mirrors the Rust firmware's compute() sequence:
//   reset → load modulus(7) → load operand(10) → start → wait → read result
//   Expected: 10^2 mod 7 = 100 mod 7 = 2

#define SIMIO  (*(volatile unsigned int *)0x10000000)

#define ACCEL_BASE  0x20000000
#define REG_CTRL    (*(volatile unsigned int *)(ACCEL_BASE + 0x00))
#define REG_STATUS  (*(volatile unsigned int *)(ACCEL_BASE + 0x04))
#define REG_OPERAND (*(volatile unsigned int *)(ACCEL_BASE + 0x08))
#define REG_RESULT  (*(volatile unsigned int *)(ACCEL_BASE + 0x0C))
#define REG_MODULUS (*(volatile unsigned int *)(ACCEL_BASE + 0x10))

#define CTRL_START    (1 << 0)
#define CTRL_RESET    (1 << 1)
#define CTRL_LOAD_OP  (1 << 2)
#define CTRL_LOAD_MOD (1 << 3)

#define STATUS_BUSY  (1 << 0)
#define STATUS_DONE  (1 << 1)
#define STATUS_ERROR (1 << 2)

static void print_str(const char *s)
{
    while (*s)
        SIMIO = *s++;
}

static char hex_digit(unsigned int nibble)
{
    nibble &= 0xF;
    if (nibble < 10)
        return '0' + nibble;
    return 'a' + (nibble - 10);
}

static void print_hex(unsigned int val)
{
    print_str("0x");
    for (int i = 28; i >= 0; i -= 4)
        SIMIO = hex_digit(val >> i);
}

void main(void)
{
    unsigned int status;
    unsigned int result;

    print_str("blindsig-soc: integration test\n");

    /* Step 1: Reset accelerator */
    REG_CTRL = CTRL_RESET;

    /* Step 2: Load modulus = 7 */
    REG_CTRL = CTRL_LOAD_MOD;
    REG_MODULUS = 7;

    /* Step 3: Load operand = 10 */
    REG_CTRL = CTRL_LOAD_OP;
    REG_OPERAND = 10;

    /* Step 4: Start computation */
    REG_CTRL = CTRL_START;

    /* Step 5: Wait for completion */
    while (REG_STATUS & STATUS_BUSY)
        ;

    /* Step 6: Check result */
    status = REG_STATUS;
    if (status & STATUS_ERROR) {
        print_str("FAIL: accelerator reported error\n");
        return;
    }

    if (!(status & STATUS_DONE)) {
        print_str("FAIL: not busy but not done either\n");
        return;
    }

    result = REG_RESULT;
    print_str("result = ");
    print_hex(result);
    print_str("\n");

    if (result == 2) {
        print_str("PASS\n");
    } else {
        print_str("FAIL: expected 2, got ");
        print_hex(result);
        print_str("\n");
    }
}

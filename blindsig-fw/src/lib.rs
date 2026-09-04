#![no_std]

use core::ptr;

const BLINDSIG_BASE: usize = 0x2000_0000;
const REG_CTRL: usize = 0x00;
const REG_STATUS: usize = 0x04;
const REG_OPERAND: usize = 0x08;
const REG_RESULT: usize = 0x0C;
const REG_MODULUS: usize = 0x10;

const CTRL_START: u32 = 1 << 0;
const CTRL_RESET: u32 = 1 << 1;
const CTRL_LOAD_OP: u32 = 1 << 2;
const CTRL_LOAD_MOD: u32 = 1 << 3;

const STATUS_BUSY: u32 = 1 << 0;
const STATUS_DONE: u32 = 1 << 1;
const STATUS_ERROR: u32 = 1 << 2;

pub struct BlindSigAccel {
    base: usize,
}

impl BlindSigAccel {
    pub const fn new(base: usize) -> Self {
        Self { base }
    }

    pub fn reset(&self) {
        mmio_write(self.base, REG_CTRL, CTRL_RESET);
    }

    pub fn is_busy(&self) -> bool {
        mmio_read(self.base, REG_STATUS) & STATUS_BUSY != 0
    }

    pub fn is_done(&self) -> bool {
        mmio_read(self.base, REG_STATUS) & STATUS_DONE != 0
    }

    pub fn is_error(&self) -> bool {
        mmio_read(self.base, REG_STATUS) & STATUS_ERROR != 0
    }

    pub fn load_modulus_word(&self, word: u32) {
        mmio_write(self.base, REG_CTRL, CTRL_LOAD_MOD);
        mmio_write(self.base, REG_MODULUS, word);
    }

    pub fn load_operand_word(&self, word: u32) {
        mmio_write(self.base, REG_CTRL, CTRL_LOAD_OP);
        mmio_write(self.base, REG_OPERAND, word);
    }

    pub fn start(&self) {
        mmio_write(self.base, REG_CTRL, CTRL_START);
    }

    pub fn wait_and_read_result(&self) -> Result<u32, ()> {
        while self.is_busy() {}
        if self.is_error() {
            return Err(());
        }
        Ok(mmio_read(self.base, REG_RESULT))
    }
}

impl BlindSigAccel {
    pub fn load_modulus(&self, words: &[u32]) {
        for word in words {
            self.load_modulus_word(*word);
        }
    }

    pub fn load_operand(&self, words: &[u32]) {
        for word in words {
            self.load_operand_word(*word);
        }
    }

    pub fn compute(&self, modulus: &[u32], operand: &[u32]) -> Result<u32, ()> {
        self.reset();


        self.load_modulus(modulus);
        self.load_operand(operand);
        self.start();
        self.wait_and_read_result()
    }
}


#[inline(always)]
fn mmio_write(base: usize, offset: usize, value: u32) {
    unsafe {
        ptr::write_volatile((base + offset) as *mut u32, value);
    }
}

#[inline(always)]
fn mmio_read(base: usize, offset: usize) -> u32 {
    unsafe {
        ptr::read_volatile((base + offset) as *const u32)
    }
}
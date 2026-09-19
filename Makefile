CROSS   ?= riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJDUMP  = $(CROSS)objdump
NM       = $(CROSS)nm

ARCH     = rv64gc
ABI      = lp64d
ISA      = rv64gc_zicntr_sstc

CFLAGS   = -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany \
           -nostdlib -nostartfiles -ffreestanding -Wl,--no-warn-rwx-segments

TARGET   = task3.elf
SRC      = task3.S
LDS      = link.ld

all: $(TARGET)

$(TARGET): $(SRC) $(LDS)
	$(CC) $(CFLAGS) -T $(LDS) -o $@ $(SRC)

run: $(TARGET)
	spike --isa=$(ISA) $(TARGET); echo "exit code = $$?"

debug: $(TARGET)
	spike -d --isa=$(ISA) $(TARGET)

trace: $(TARGET)
	spike -l --log-commits --isa=$(ISA) $(TARGET) 2> trace.log; \
	echo "trace written to trace.log"

dump: $(TARGET)
	$(OBJDUMP) -d -M no-aliases $(TARGET) | less

syms: $(TARGET)
	$(NM) $(TARGET) | grep -E 'tohost|fromhost|_start|s_mode'

clean:
	rm -f $(TARGET) trace.log

.PHONY: all run debug trace dump syms clean
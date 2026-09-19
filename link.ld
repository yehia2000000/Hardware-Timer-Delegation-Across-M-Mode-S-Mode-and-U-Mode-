ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    .text : ALIGN(4)
    {
        *(.text.init)
        *(.text)
        *(.text.*)
    } > RAM

    .rodata : ALIGN(8)
    {
        *(.rodata)
        *(.rodata.*)
    } > RAM

    .data : ALIGN(8)
    {
        *(.data)
        *(.data.*)
    } > RAM

    .bss : ALIGN(8)
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
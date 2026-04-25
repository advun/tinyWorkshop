![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout Low Area Trace Data Compressor by advun

- [Read the documentation for project](docs/info.md)

TL;DR: This is a lossless low area data compressor for compressing trace data on a chip, originally designed for an FPGA for GoatHacks 2026 winning best Rookie Hack.  The original project can be found [here](https://github.com/advun/goathacksCompressor), though it was made in 30 hours by one person and is quite rough.  This uses the same simple compression algorithm to compress the real time data from an 8 bit trace with up to a 255x compression rate in this implementation, while only requiring 358 logic cells and 50 flip flops.  The compressor can be so small while accomplishing such high compression by taking advantage of common digital signal behaviors, explained further in the documentation.  I have made it as easy to tweak to different size traces as possible, as the larger the bus being compressed, the greater the compression ratio compared to raw data. 

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)
- [Submit your design to the next shuttle](https://app.tinytapeout.com/).

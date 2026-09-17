# Nintendo FPGA

FPGA-based Nintendo Entertainment System implementation targeting the Terasic DE1-SoC and its Intel Cyclone V SoC FPGA.

## Development Environment

- Terasic DE1-SoC
- Intel Cyclone V SoC
- Quartus Prime Lite 23.1.1
- SystemVerilog
- Verilator
- VaporView / waveform analysis
- openFPGALoader
- USB-Blaster II
- VS Code Remote SSH
- Tailscale remote development

## Project Structure

- `rtl/cpu` - CPU implementation
- `rtl/ppu` - Picture Processing Unit
- `rtl/apu` - Audio Processing Unit
- `rtl/memory` - memory subsystem
- `rtl/cartridge` - cartridge interface
- `rtl/controller` - controller interface
- `rtl/video` - video output pipeline
- `sim` - simulation and testbenches
- `constraints` - FPGA pin and timing constraints
- `quartus` - Quartus project files
- `scripts` - build, simulation and deployment scripts
- `docs` - architecture and engineering documentation

## Development Flow

SystemVerilog
→ Verilator simulation
→ waveform verification
→ Quartus synthesis/fitting
→ RBF generation
→ Tailscale transfer
→ openFPGALoader
→ USB-Blaster II
→ DE1-SoC

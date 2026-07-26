## ---------------------------------------------------------------------------
## SDMapper.sdc
## Timing constraints for the MSX SD Mapper / Multicart project
## (SDMapper_Top.vhd, spi.vhd, exp_slot.vhd)
## ---------------------------------------------------------------------------
## Named "SDMapper.sdc" to match the filename Quartus is already looking for
## (per Critical Warning 332012), so the Quartus project settings do not need
## to be changed - just drop this file into the project directory.
## ---------------------------------------------------------------------------

## ---------------------------------------------------------------------------
## Base board clock
## ---------------------------------------------------------------------------
create_clock -name {CLOCK_50} -period 20.000 [get_ports {CLOCK_50}]

## Automatically derive clock_i (25MHz, from clock_25mhz_inst) and any other
## PLL-generated clocks in the design from CLOCK_50.
derive_pll_clocks

## Account for PLL jitter / phase uncertainty in the timing analysis.
derive_clock_uncertainty

## ---------------------------------------------------------------------------
## Asynchronous MSX bus inputs
## ---------------------------------------------------------------------------
## A, D, RD_n, WR_n, MREQ_n, IORQ_n, SLTSL_n, M1_n, CS_n and RESET_n are all
## genuinely asynchronous to clock_i by design - that is exactly why every
## register they reach goes through a synchronizer first (see SDMapper_Top.vhd,
## spi.vhd, exp_slot.vhd) rather than being treated as synchronous inputs.
##
## TimeQuest cannot meaningfully check setup/hold on the first synchronizer
## stage, since there is no fixed timing relationship between these signals
## and clock_i to check against - "unconstrained" is not the same as
## "intentionally asynchronous" as far as the tool is concerned, so without
## this false-path declaration TimeQuest will report these as failing paths.
##
## This is matched against every synchronizer front-end register in the
## design (all end in "_meta", confirmed across SDMapper_Top.vhd, spi.vhd and
## exp_slot.vhd): wr_n_meta, s_iorq_w_reg_meta, spi_ctrl_wr_meta,
## spi_ctrl_rd_meta, spi_cs_meta, rd_n_meta, sltsl_n_meta, cpu_wr_n_meta,
## ffff_meta.
set_false_path -from [get_ports {A[*] D[*] RD_n WR_n MREQ_n IORQ_n SLTSL_n M1_n CS_n RESET_n}] -to [get_registers {*_meta}]

## ---------------------------------------------------------------------------
## Asynchronous board-level inputs (switches, pushbuttons)
## ---------------------------------------------------------------------------
## SW and KEY are slow, manually-operated inputs used for configuration/reset
## and are not part of the MSX bus timing-critical path. Excluded from timing
## analysis to avoid spurious failing paths from these signals.
set_false_path -from [get_ports {SW[*] KEY[*]}]

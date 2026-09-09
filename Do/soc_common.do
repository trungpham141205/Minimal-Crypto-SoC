# Shared setup for the three SoC tests. Invoke their scripts from KLTN root.
transcript on
onerror {quit -force -code 1}
onbreak {resume}

proc soc_prepare {top firmware} {
    global soc_project_root
    set soc_project_root [pwd]
    set tb "TB/${top}.sv"
    foreach path [list filelist_soc.f soc_top.sv $tb $firmware] {
        if {![file isfile $path]} {
            error "Missing $path. Run vsim from the KLTN project root."
        }
    }

    # Separate library, firmware copy and simulation outputs for each test.
    # instruction_memory still reads program.hex; no RTL change is needed.
    set run_dir [file join $soc_project_root sim $top]
    set lib_dir [file join $run_dir work]
    file mkdir $run_dir
    if {![file isdirectory $lib_dir]} {
        vlib $lib_dir
    }
    vmap work $lib_dir
    vlog -sv -work work -f filelist_soc.f
    vlog -sv -work work $tb
    file copy -force $firmware [file join $run_dir program.hex]
    puts "TEST: $top | FIRMWARE: $firmware | OUTPUT: $run_dir"
    cd $run_dir
    vsim -onfinish stop -voptargs=+acc -wlf "${top}.wlf" work.$top
}

proc soc_sram_waves {top} {
    foreach instance {u_shared_sram_slave u_instruction_sram_slave} {
        set base "sim:/${top}/dut/${instance}"
        catch {add wave -divider $instance}
        foreach signal {sram_me sram_we} {
            catch {add wave ${base}/${signal}}
        }
        foreach signal {sram_addr sram_wdata sram_rdata} {
            catch {add wave -hex ${base}/${signal}}
        }
        foreach signal {wstate_q rstate_q aw_captured_q w_captured_q} {
            catch {add wave ${base}/u_ctrl/${signal}}
        }
    }
}

proc soc_run {top} {
    run -all
    # A timeout/$fatal/break must not be reported as a passing batch run.
    set passed [examine -radix unsigned sim:/${top}/test_passed]
    if {$passed ne "1"} {
        puts "FAIL: $top did not complete its checks."
        quit -force -code 1
    }
    puts "PASS: $top"
}

#!/system/bin/sh
# Copyright (c) 2012-2013, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

target=`getprop ro.board.platform`

function configure_memory_parameters() {
# Set Memory paremeters.
#
# Set per_process_reclaim tuning parameters
# 2GB 64-bit will have aggressive settings when compared to 1GB 32-bit
# 1GB and less will use vmpressure range 50-70, 2GB will use 10-70
# 1GB and less will use 512 pages swap size, 2GB will use 1024
#
# Set Low memory killer minfree parameters
# 32 bit all memory configurations will use 15K series
# 64 bit up to 2GB with use 14K, and above 2GB will use 18K
#
# Set ALMK parameters (usually above the highest minfree values)
# 32 bit will have 53K & 64 bit will have 81K
#

    arch_type=`uname -m`
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}

    if [ $MemTotal -le 2097152 ]; then
        #Enable B service adj transition for 2GB or less memory
        setprop ro.sys.fw.bservice_enable true
        setprop ro.sys.fw.bservice_limit 5
        setprop ro.sys.fw.bservice_age 5000
        #Enable Delay Service Restart
        setprop ro.am.reschedule_service true
    fi

    # Set background app limit to 60 for 64 bit config with memory greater than 3.5 GB
    # Also set swappiness to 60
    # Disable process reclaim on 64 bit config with memory greater than 3.5 GB
    if [ $MemTotal -gt 3670016 ] && [ "$arch_type" == "aarch64" ]; then
        setprop ro.sys.fw.bg_apps_limit 60
        echo 60 > /proc/sys/vm/swappiness
        echo 0 > /sys/module/process_reclaim/parameters/enable_process_reclaim
    fi

    # Read adj series and set adj threshold for PPR and ALMK.
    # This is required since adj values change from framework to framework.
    adj_series=`cat /sys/module/lowmemorykiller/parameters/adj`
    adj_1="${adj_series#*,}"
    set_almk_ppr_adj="${adj_1%%,*}"

    # PPR and ALMK should not act on HOME adj and below.
    # Normalized ADJ for HOME is 6. Hence multiply by 6
    # ADJ score represented as INT in LMK params, actual score can be in decimal
    # Hence add 6 considering a worst case of 0.9 conversion to INT (0.9*6).
    set_almk_ppr_adj=$(((set_almk_ppr_adj * 6) + 6))
    echo $set_almk_ppr_adj > /sys/module/lowmemorykiller/parameters/adj_max_shift
    echo $set_almk_ppr_adj > /sys/module/process_reclaim/parameters/min_score_adj

    # Enable and configure process reclaim with memory less than 3.5 GB
    if [ $MemTotal -lt 3670016 ]; then
        echo 1 > /sys/module/process_reclaim/parameters/enable_process_reclaim
        echo 70 > /sys/module/process_reclaim/parameters/pressure_max
        echo 30 > /sys/module/process_reclaim/parameters/swap_opt_eff
    fi

    echo 1 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk
    if [ "$arch_type" == "aarch64" ] && [ $MemTotal -gt 2097152 ]; then
        echo 10 > /sys/module/process_reclaim/parameters/pressure_min
        echo 1024 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
    elif [ "$arch_type" == "aarch64" ] && [ $MemTotal -gt 1048576 ]; then
        echo 10 > /sys/module/process_reclaim/parameters/pressure_min
        echo 1024 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "14746,18432,22118,25805,40000,55000" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
    elif [ "$arch_type" == "aarch64" ]; then
        echo 50 > /sys/module/process_reclaim/parameters/pressure_min
        echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "14746,18432,22118,25805,40000,55000" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
    else
        echo 50 > /sys/module/process_reclaim/parameters/pressure_min
        echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "15360,19200,23040,26880,34415,43737" > /sys/module/lowmemorykiller/parameters/minfree
        echo 53059 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
    fi

    # Zram disk - 512MB size
    zram_enable=`getprop ro.config.zram`
    if [ "$zram_enable" == "true" ]; then

        if [ $MemTotal -le 2097152 ]; then
            echo 792723456 > /sys/block/zram0/disksize
        else
            echo 536870912 > /sys/block/zram0/disksize
        fi

        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi
}

case "$target" in
    "msm8952")

        if [ -f /sys/devices/soc0/soc_id ]; then
            soc_id=`cat /sys/devices/soc0/soc_id`
        else
            soc_id=`cat /sys/devices/system/soc/soc0/id`
        fi
        case "$soc_id" in
            "264" | "289")
                # Apply Scheduler and Governor settings for 8952

                # HMP scheduler settings
                echo 3 > /proc/sys/kernel/sched_window_stats_policy
                echo 3 > /proc/sys/kernel/sched_ravg_hist_size
                echo 20000000 > /proc/sys/kernel/sched_ravg_window

                # HMP Task packing settings
                echo 20 > /proc/sys/kernel/sched_small_task
                echo 30 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_load
                echo 30 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_load

                echo 3 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_nr_run

                echo 0 > /sys/devices/system/cpu/cpu0/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu1/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu2/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu3/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu4/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu5/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu6/sched_prefer_idle
                echo 0 > /sys/devices/system/cpu/cpu7/sched_prefer_idle

                echo 0 > /proc/sys/kernel/sched_boost

                for devfreq_gov in /sys/class/devfreq/qcom,mincpubw*/governor
                do
                    echo "cpufreq" > $devfreq_gov
                done

                for devfreq_gov in /sys/class/devfreq/qcom,cpubw*/governor
                do
                    echo "bw_hwmon" > $devfreq_gov
                    for cpu_io_percent in /sys/class/devfreq/qcom,cpubw*/bw_hwmon/io_percent
                    do
                        echo 20 > $cpu_io_percent
                    done
                    for cpu_guard_band in /sys/class/devfreq/qcom,cpubw*/bw_hwmon/guard_band_mbps
                    do
                        echo 30 > $cpu_guard_band
                    done
                done

                for gpu_bimc_io_percent in /sys/class/devfreq/qcom,gpubw*/bw_hwmon/io_percent
                do
                    echo 40 > $gpu_bimc_io_percent
                done
                # disable thermal & BCL core_control to update interactive gov settings
                echo 0 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    bcl_hotplug_mask=`cat $hotplug_mask`
                    echo 0 > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    bcl_soc_hotplug_mask=`cat $hotplug_soc_mask`
                    echo 0 > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                # enable governor for perf cluster
                echo 1 > /sys/devices/system/cpu/cpu0/online
                echo "interactive" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
                echo "19000 1113600:39000" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/above_hispeed_delay
                echo 85 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/go_hispeed_load
                echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/timer_rate
                echo 1113600 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq
                echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/io_is_busy
                echo "1 960000:85 1113600:90 1344000:80" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/target_loads
                echo 40000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/min_sample_time
                echo 40000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/sampling_down_factor
                echo 960000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

                # enable governor for power cluster
                echo 1 > /sys/devices/system/cpu/cpu4/online
                echo "interactive" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
                echo 39000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/above_hispeed_delay
                echo 90 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/go_hispeed_load
                echo 20000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/timer_rate
                echo 806400 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/hispeed_freq
                echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/io_is_busy
                echo "1 806400:90" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/target_loads
                echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/min_sample_time
                echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/sampling_down_factor
                echo 806400 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq

                # Bring up all cores online
                echo 1 > /sys/devices/system/cpu/cpu1/online
                echo 1 > /sys/devices/system/cpu/cpu2/online
                echo 1 > /sys/devices/system/cpu/cpu3/online
                echo 1 > /sys/devices/system/cpu/cpu4/online
                echo 1 > /sys/devices/system/cpu/cpu5/online
                echo 1 > /sys/devices/system/cpu/cpu6/online
                echo 1 > /sys/devices/system/cpu/cpu7/online

                # Enable Low power modes
                echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

                # HMP scheduler (big.Little cluster related) settings
                echo 93 > /proc/sys/kernel/sched_upmigrate
                echo 83 > /proc/sys/kernel/sched_downmigrate

                # Enable sched guided freq control
                echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_sched_load
                echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_migration_notif
                echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_sched_load
                echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_migration_notif
                echo 50000 > /proc/sys/kernel/sched_freq_inc_notify
                echo 50000 > /proc/sys/kernel/sched_freq_dec_notify

                # Enable core control
                echo 2 > /sys/devices/system/cpu/cpu0/core_ctl/min_cpus
                echo 4 > /sys/devices/system/cpu/cpu0/core_ctl/max_cpus
                echo 68 > /sys/devices/system/cpu/cpu0/core_ctl/busy_up_thres
                echo 40 > /sys/devices/system/cpu/cpu0/core_ctl/busy_down_thres
                echo 100 > /sys/devices/system/cpu/cpu0/core_ctl/offline_delay_ms
                echo 1 > /sys/devices/system/cpu/cpu0/core_ctl/is_big_cluster

                # re-enable thermal & BCL core_control now
                echo 1 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    echo $bcl_hotplug_mask > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    echo $bcl_soc_hotplug_mask > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                # Enable dynamic clock gating
                echo 1 > /sys/module/lpm_levels/lpm_workarounds/dynamic_clock_gating
                # Enable timer migration to little cluster
                echo 1 > /proc/sys/kernel/power_aware_timer_migration
            ;;
            *)
                panel=`cat /sys/class/graphics/fb0/modes`
                if [ "${panel:5:1}" == "x" ]; then
                    panel=${panel:2:3}
                else
                    panel=${panel:2:4}
                fi

                # Apply Scheduler and Governor settings for 8976
                # SoC IDs are 266, 274, 277, 278

                # HMP scheduler (big.Little cluster related) settings
                echo 95 > /proc/sys/kernel/sched_upmigrate
                echo 85 > /proc/sys/kernel/sched_downmigrate

                echo 2 > /proc/sys/kernel/sched_window_stats_policy
                echo 5 > /proc/sys/kernel/sched_ravg_hist_size

                echo 3 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_nr_run
                echo 3 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_nr_run

                for devfreq_gov in /sys/class/devfreq/qcom,mincpubw*/governor
                do
                    echo "cpufreq" > $devfreq_gov
                done

                for devfreq_gov in /sys/class/devfreq/qcom,cpubw*/governor
                do
                    echo "bw_hwmon" > $devfreq_gov
                    for cpu_io_percent in /sys/class/devfreq/qcom,cpubw*/bw_hwmon/io_percent
                    do
                        echo 20 > $cpu_io_percent
                    done
                    for cpu_guard_band in /sys/class/devfreq/qcom,cpubw*/bw_hwmon/guard_band_mbps
                    do
                        echo 30 > $cpu_guard_band
                    done
                done

                for gpu_bimc_io_percent in /sys/class/devfreq/qcom,gpubw*/bw_hwmon/io_percent
                do
                    echo 40 > $gpu_bimc_io_percent
                done
                # disable thermal & BCL core_control to update interactive gov settings
                echo 0 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    bcl_hotplug_mask=`cat $hotplug_mask`
                    echo 0 > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    bcl_soc_hotplug_mask=`cat $hotplug_soc_mask`
                    echo 0 > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                # enable governor for power cluster
                echo 1 > /sys/devices/system/cpu/cpu0/online
                echo "interactive" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
                echo 80 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/go_hispeed_load
                echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/timer_rate
                echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/io_is_busy
                echo 40000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/min_sample_time
                echo 691200 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

                # enable governor for perf cluster
                echo 1 > /sys/devices/system/cpu/cpu4/online
                echo "interactive" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
                echo 85 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/go_hispeed_load
                echo 20000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/timer_rate
                echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/io_is_busy
                echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/min_sample_time
                echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/sampling_down_factor
                echo 883200 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
                echo 60000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/max_freq_hysteresis

                echo 59000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/above_hispeed_delay
                echo 1305600 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq
                echo "1 691200:80" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/target_loads
                echo 1382400 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/hispeed_freq
                echo "19000 1382400:39000" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/above_hispeed_delay
                echo "85 1382400:90 1747200:80" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/target_loads
                # HMP Task packing settings for 8976
                echo 30 > /proc/sys/kernel/sched_small_task
                echo 20 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_load
                echo 20 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_load

                echo 0 > /proc/sys/kernel/sched_boost

                # Bring up all cores online
                echo 1 > /sys/devices/system/cpu/cpu1/online
                echo 1 > /sys/devices/system/cpu/cpu2/online
                echo 1 > /sys/devices/system/cpu/cpu3/online
                echo 1 > /sys/devices/system/cpu/cpu4/online
                echo 1 > /sys/devices/system/cpu/cpu5/online
                echo 1 > /sys/devices/system/cpu/cpu6/online
                echo 1 > /sys/devices/system/cpu/cpu7/online

                #Disable CPU retention modes for 32bit builds
                ProductName=`getprop ro.product.name`
                if [ "$ProductName" == "msm8952_32" ] || [ "$ProductName" == "msm8952_32_LMT" ] || [ "$ProductName" == "Aquaris_X5_Plus" ]; then
                    echo N > /sys/module/lpm_levels/system/a72/cpu4/retention/idle_enabled
                    echo N > /sys/module/lpm_levels/system/a72/cpu5/retention/idle_enabled
                    echo N > /sys/module/lpm_levels/system/a72/cpu6/retention/idle_enabled
                    echo N > /sys/module/lpm_levels/system/a72/cpu7/retention/idle_enabled
                fi

		if [ `cat /sys/devices/soc0/revision` == "1.0" ]; then
		    # Disable l2-pc and l2-gdhs low power modes
		    echo N > /sys/module/lpm_levels/system/a53/a53-l2-gdhs/idle_enabled
		    echo N > /sys/module/lpm_levels/system/a72/a72-l2-gdhs/idle_enabled
		    echo N > /sys/module/lpm_levels/system/a53/a53-l2-pc/idle_enabled
		    echo N > /sys/module/lpm_levels/system/a72/a72-l2-pc/idle_enabled
		fi

                # Enable LPM Prediction
                echo 1 > /sys/module/lpm_levels/parameters/lpm_prediction

                # Enable Low power modes
                echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled
                # Disable L2 GDHS on 8976
                echo N > /sys/module/lpm_levels/system/a53/a53-l2-gdhs/idle_enabled
                echo N > /sys/module/lpm_levels/system/a72/a72-l2-gdhs/idle_enabled

                # Enable sched guided freq control
                echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_sched_load
                echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_migration_notif
                echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_sched_load
                echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_migration_notif
                echo 50000 > /proc/sys/kernel/sched_freq_inc_notify
                echo 50000 > /proc/sys/kernel/sched_freq_dec_notify

                # Enable core control
                echo 2 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
                echo 4 > /sys/devices/system/cpu/cpu4/core_ctl/max_cpus
                echo 68 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
                echo 40 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
                echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
                echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/is_big_cluster

                # re-enable thermal & BCL core_control now
                echo 1 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    echo $bcl_hotplug_mask > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    echo $bcl_soc_hotplug_mask > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                # Enable timer migration to little cluster
                echo 1 > /proc/sys/kernel/power_aware_timer_migration

		case "$soc_id" in
			"277" | "278")
			# Start energy-awareness for 8976
			start energy-awareness
		;;
		esac

		#enable sched colocation and colocation inheritance
		echo 130 > /proc/sys/kernel/sched_grp_upmigrate
		echo 110 > /proc/sys/kernel/sched_grp_downmigrate
		echo   1 > /proc/sys/kernel/sched_enable_thread_grouping
            ;;
        esac

        # Set Memory parameters
        configure_memory_parameters
	restorecon -R /sys/devices/system/cpu
    ;;
esac

chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/io_is_busy

# Post-setup services
case "$target" in
    "msm8952")
        rm /data/system/perfd/default_values
        start perfd
    ;;
esac

if [ -f /sys/devices/soc0/select_image ]; then
    # Let kernel know our image version/variant/crm_version
    image_version="10:"
    image_version+=`getprop ro.build.id`
    image_version+=":"
    image_version+=`getprop ro.build.version.incremental`
    image_variant=`getprop ro.product.name`
    image_variant+="-"
    image_variant+=`getprop ro.build.type`
    oem_version=`getprop ro.build.version.codename`
    echo 10 > /sys/devices/soc0/select_image
    echo $image_version > /sys/devices/soc0/image_version
    echo $image_variant > /sys/devices/soc0/image_variant
    echo $oem_version > /sys/devices/soc0/image_crm_version
fi

package main

import (
	"strings"

	"github.com/tw93/mole/internal/i18n"
)

func statusDiagnosisLine(m MetricsSnapshot) string {
	for _, disk := range m.Disks {
		if disk.SmartStatus == smartStatusFailing {
			return i18n.T("status_smart_failing")
		}
	}
	if m.CPU.Usage > cpuHighThreshold {
		if processSnapshotFresh(m.ProcessStale) {
			if proc, ok := leadingCPUProcess(m.TopProcesses, 50); ok {
				return i18n.T("status_process_cpu_high", shorten(proc.Name, 18))
			}
		}
		return i18n.T("status_cpu_high")
	}
	if m.Memory.Pressure == "warn" || m.Memory.Pressure == "critical" || m.Memory.UsedPercent > memHighThreshold {
		if processSnapshotFresh(m.ProcessStale) {
			if proc, ok := leadingMemoryProcess(m.TopProcesses); ok && proc.Memory > 0 {
				return i18n.T("status_process_memory_pressure", shorten(proc.Name, 18))
			}
		}
		return i18n.T("status_memory_high")
	}
	if disk, ok := rootDisk(m.Disks); ok && diskIsCritical(disk) {
		free := uint64(0)
		if disk.Total > disk.Used {
			free = disk.Total - disk.Used
		}
		return i18n.T("status_disk_low", humanBytesShort(free))
	}
	for _, battery := range m.Batteries {
		if battery.Capacity > 0 && battery.Capacity < batteryCapWarn {
			return i18n.T("status_battery_low")
		}
		if battery.CycleCount > batteryCycleWarn {
			return i18n.T("status_battery_cycles_high")
		}
	}
	if m.Thermal.CPUTemp > thermalNormalThreshold {
		return i18n.T("status_temperature_high")
	}
	if totalIO := m.DiskIO.ReadRate + m.DiskIO.WriteRate; totalIO > ioHighThreshold {
		return i18n.T("status_disk_io_busy")
	}
	if strings.Contains(m.HealthScoreMsg, ":") {
		return localizedHealthScoreMessage(m.HealthScoreMsg)
	}
	return i18n.T("status_all_clear")
}

func localizedHealthScoreMessage(message string) string {
	replacements := []struct{ source, key string }{
		{"Needs Attention", "status_score_attention"},
		{"Excellent", "status_score_excellent"},
		{"Good", "status_score_good"},
		{"Fair", "status_score_fair"},
		{"High Memory", "status_issue_high_memory"},
		{"Memory Pressure", "status_issue_memory_pressure"},
		{"Critical Memory", "status_issue_critical_memory"},
		{"Disk Almost Full", "status_issue_disk_almost_full"},
		{"Disk SMART Failing", "status_issue_disk_smart_failing"},
		{"Overheating", "status_issue_overheating"},
		{"Heavy Disk IO", "status_issue_heavy_disk_io"},
		{"Battery Service Soon", "status_issue_battery_service"},
		{"Restart Recommended", "status_issue_restart_recommended"},
	}
	for _, replacement := range replacements {
		message = strings.ReplaceAll(message, replacement.source, i18n.T(replacement.key))
	}
	return message
}

func leadingCPUProcess(procs []ProcessInfo, threshold float64) (ProcessInfo, bool) {
	var best ProcessInfo
	for i, proc := range procs {
		if i == 0 || proc.CPU > best.CPU {
			best = proc
		}
	}
	if best.CPU < threshold {
		return ProcessInfo{}, false
	}
	return best, true
}

func leadingMemoryProcess(procs []ProcessInfo) (ProcessInfo, bool) {
	var best ProcessInfo
	for i, proc := range procs {
		if i == 0 || proc.Memory > best.Memory {
			best = proc
		}
	}
	return best, len(procs) > 0
}

func rootDisk(disks []DiskStatus) (DiskStatus, bool) {
	for _, disk := range disks {
		if disk.Mount == "/" {
			return disk, true
		}
	}
	if len(disks) == 0 {
		return DiskStatus{}, false
	}
	return disks[0], true
}

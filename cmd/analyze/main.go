//go:build darwin

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/tw93/mole/internal/i18n"
)

var (
	jsonMode = flag.Bool("json", false, i18n.T("analyze_flag_json"))
)

// usageText is the help every other Mole subcommand prints by hand. The Go flag
// package would otherwise render "Usage of /usr/local/bin/analyze-go:", naming a
// bundled binary the user never typed, so the text is written out here instead.
func usageText() string {
	return fmt.Sprintf("%s\n\n%s\n\n%s\n  --json          %s\n  -h, --help      %s\n\n%s\n  mo analyze                 %s\n  mo analyze ~/Library       %s\n  mo analyze --json /Volumes %s\n",
		i18n.T("help_usage", "analyze [OPTIONS] [PATH]"), i18n.T("analyze_help_description"), i18n.T("help_options"),
		i18n.T("analyze_help_json"), i18n.T("help_option_help"), i18n.T("help_examples"),
		i18n.T("analyze_example_overview"), i18n.T("analyze_example_directory"), i18n.T("analyze_example_json"))
}

// parseArgs applies Mole's CLI conventions to the flag package: help goes to
// stdout and exits 0, and an unknown flag goes to stderr and exits 1 the way
// every bash subcommand does, rather than the flag package's stderr-and-2.
// It returns the exit code and whether main should keep running.
func parseArgs(args []string, stdout, stderr io.Writer) (int, bool) {
	flag.CommandLine.Init("mo analyze", flag.ContinueOnError)
	// Parse must not print: this function decides which stream each message
	// belongs on, and the default handler writes usage to stderr for both.
	flag.CommandLine.SetOutput(io.Discard)
	flag.CommandLine.Usage = func() {}

	err := flag.CommandLine.Parse(args)
	switch {
	case errors.Is(err, flag.ErrHelp):
		_, _ = fmt.Fprint(stdout, usageText())
		return 0, false
	case err != nil:
		_, _ = fmt.Fprintln(stderr, localizedAnalyzeFlagError(err))
		_, _ = fmt.Fprintln(stderr, i18n.T("analyze_error_hint"))
		return 1, false
	}
	return 0, true
}

func localizedAnalyzeFlagError(err error) string {
	const unknownFlagPrefix = "flag provided but not defined: "
	if flag, found := strings.CutPrefix(err.Error(), unknownFlagPrefix); found {
		return i18n.T("analyze_unknown_flag", flag)
	}
	return err.Error()
}

func main() {
	if code, keepGoing := parseArgs(os.Args[1:], os.Stdout, os.Stderr); !keepGoing {
		os.Exit(code)
	}

	abs, isOverview, err := resolveScanTarget(os.Getenv("MO_ANALYZE_PATH"), flag.Args())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	go pruneAnalyzerCache()
	if *jsonMode {
		runJSONMode(abs, isOverview)
	} else {
		runTUIMode(abs, isOverview)
	}
}

// resolveScanTarget decides which scan a given invocation asks for. Kept
// separate from main so the overview-vs-directory routing has a test that fails
// when it flips: an end-to-end overview scan measures the real /Applications
// and /Library, which cost 106s of a single CI test file's 134s.
func resolveScanTarget(envPath string, args []string) (string, bool, error) {
	target := envPath
	if target == "" && len(args) > 0 {
		target = args[0]
	}

	// No explicit target means the machine-wide overview, not the root
	// directory: "/" is only where the overview rows are anchored.
	if target == "" {
		return "/", true, nil
	}

	abs, err := filepath.Abs(target)
	if err != nil {
		return "", false, fmt.Errorf(i18n.T("analyze_cannot_resolve"), target, err)
	}
	return abs, false, nil
}

func runTUIMode(path string, isOverview bool) {
	m := newModel(path, isOverview)
	defer m.cancelBackgroundCacheWrites(nil)
	// Warm overview cache only when the user opens a specific directory.
	// Overview mode already schedules the same measurements for the foreground UI;
	// running the prefetcher there doubles the du/io workload on cold start.
	if !isOverview {
		prefetchCtx, prefetchCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer prefetchCancel()
		m.startOverviewPrefetch(prefetchCtx)
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, i18n.T("analyze_error_prefix")+"\n", err)
		os.Exit(1)
	}
}

func newModel(path string, isOverview bool) model {
	var filesScanned, dirsScanned, bytesScanned int64
	currentPath := &atomic.Value{}
	currentPath.Store("")
	var diskFreeBytes int64
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err == nil {
		diskFreeBytes = int64(stat.Bavail) * int64(stat.Bsize)
	}

	m := model{
		path:                path,
		selected:            0,
		status:              i18n.T("analyze_prepare"),
		diskFree:            diskFreeBytes,
		scanning:            !isOverview,
		filesScanned:        &filesScanned,
		dirsScanned:         &dirsScanned,
		bytesScanned:        &bytesScanned,
		currentPath:         currentPath,
		showLargeFiles:      false,
		isOverview:          isOverview,
		cache:               make(map[string]historyEntry),
		overviewSizeCache:   make(map[string]int64),
		overviewScanningSet: make(map[string]*scanPublication),
		cachePublications:   make(map[string]*scanPublication),
		multiSelected:       make(map[string]bool),
		largeMultiSelected:  make(map[string]bool),
		liveSortMode:        liveSortFreezeOnMove,
		snapshotRunner:      runLocalSnapshotCommand,
	}

	if isOverview {
		m.scanning = false
		m.hydrateOverviewEntries()
		m.selected = 0
		m.offset = 0
		if nextPendingOverviewIndex(m.entries) >= 0 {
			m.overviewScanning = true
			m.status = i18n.T("analyze_checking_system")
		} else {
			m.status = i18n.T("analyze_ready")
		}
	}

	// Try to peek last total files for progress bar, even if cache is stale
	if !isOverview {
		if total, err := peekCacheTotalFiles(path); err == nil && total > 0 {
			m.lastTotalFiles = total
		}
	}

	return m
}

func createOverviewEntries() []dirEntry {
	return createOverviewEntriesWithInsights(createInsightEntries())
}

func createOverviewEntriesWithInsights(insightEntries []dirEntry) []dirEntry {
	home := os.Getenv("HOME")
	entries := []dirEntry{}

	// Separate Home and ~/Library to avoid double counting.
	if home != "" {
		entries = append(entries, dirEntry{Name: "Home", Path: home, IsDir: true, Size: -1})

		userLibrary := filepath.Join(home, "Library")
		if _, err := os.Stat(userLibrary); err == nil {
			// Renamed from "App Library" to "User Library" so it parallels
			// "System Library" (`/Library`) and is not confused with
			// `/Applications`. Path unchanged.
			entries = append(entries, dirEntry{Name: "User Library", Path: userLibrary, IsDir: true, Size: -1})
		}
	}

	entries = append(entries, systemOverviewRoots()...)
	entries = append(entries, mountedVolumeOverviewEntries()...)

	// Hidden space insights: paths that silently accumulate disk usage.
	entries = append(entries, insightEntries...)

	return entries
}

func systemOverviewRoots() []dirEntry {
	return []dirEntry{
		{Name: "Applications", Path: "/Applications", IsDir: true, Size: -1},
		{Name: "System Library", Path: "/Library", IsDir: true, Size: -1},
	}
}

func overviewEntryDisplayName(name string) string {
	switch name {
	case "Home":
		return i18n.T("analyze_home")
	case "User Library":
		return i18n.T("analyze_user_library")
	case "Applications":
		return i18n.T("analyze_applications")
	case "System Library":
		return i18n.T("analyze_system_library")
	default:
		// Insight names stay English in dirEntry.Name and JSON output; only
		// the overview rendering looks up a localized label.
		if key, ok := insightDisplayKeys[name]; ok {
			return i18n.T(key)
		}
		return name
	}
}

var insightDisplayKeys = map[string]string{
	"iOS Backups":          "analyze_insight_ios_backups",
	"Old Downloads (90d+)": "analyze_insight_old_downloads",
	"System Logs":          "analyze_insight_system_logs",
	"Homebrew Cache":       "analyze_insight_homebrew_cache",
	"Xcode DerivedData":    "analyze_insight_xcode_derived_data",
	"Xcode Simulators":     "analyze_insight_xcode_simulators",
	"Xcode Archives":       "analyze_insight_xcode_archives",
	"Spotify Cache":        "analyze_insight_spotify_cache",
	"JetBrains Cache":      "analyze_insight_jetbrains_cache",
	"Docker Data":          "analyze_insight_docker_data",
	"pip Cache":            "analyze_insight_pip_cache",
	"uv Cache":             "analyze_insight_uv_cache",
	"Gradle Cache":         "analyze_insight_gradle_cache",
	"CocoaPods Cache":      "analyze_insight_cocoapods_cache",
	"OrbStack Data":        "analyze_insight_orbstack_data",
}

func sumKnownEntrySizes(entries []dirEntry) int64 {
	var total int64
	for _, entry := range entries {
		if entry.Size > 0 {
			total += entry.Size
		}
	}
	return total
}

func nextPendingOverviewIndex(entries []dirEntry) int {
	for i, entry := range entries {
		if entry.Size < 0 {
			return i
		}
	}
	return -1
}

func hasPendingOverviewEntries(entries []dirEntry) bool {
	for _, entry := range entries {
		if entry.Size < 0 {
			return true
		}
	}
	return false
}

func safeOpen(path string, reveal bool) error {
	if err := validatePath(path); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), openCommandTimeout)
	defer cancel()
	args := []string{path}
	if reveal {
		args = []string{"-R", path}
	}
	return exec.CommandContext(ctx, "open", args...).Run()
}

// safePreview opens the file with the default macOS application.
func safePreview(path string) error {
	if err := validatePath(path); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), openCommandTimeout)
	defer cancel()
	return exec.CommandContext(ctx, "open", path).Run()
}

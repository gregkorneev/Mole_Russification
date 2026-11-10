//go:build darwin

package main

import "github.com/tw93/mole/internal/i18n"

func nextLiveSortMode(mode liveSortMode) liveSortMode {
	if mode == liveSortContinuous {
		return liveSortFreezeOnMove
	}
	return liveSortContinuous
}

func liveSortModeLabel(mode liveSortMode) string {
	if mode == liveSortFreezeOnMove {
		return i18n.T("analyze_live_sort_freeze")
	}
	return i18n.T("analyze_live_sort_continuous")
}

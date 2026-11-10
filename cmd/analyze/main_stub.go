//go:build !darwin

package main

import (
	"fmt"
	"os"

	"github.com/tw93/mole/internal/i18n"
)

func main() {
	fmt.Fprintln(os.Stderr, i18n.T("analyze_not_macos"))
	os.Exit(1)
}

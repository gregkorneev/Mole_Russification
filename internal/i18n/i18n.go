// Package i18n reads the shared, dependency-free TSV catalogs used by Mole's
// Bash commands and Go terminal interfaces.
package i18n

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Catalog stores the selected language and its English fallback.
type Catalog struct {
	selected map[string]string
	english  map[string]string
}

var defaultCatalog = FromEnvironment()

// T is the process-wide translation helper for command-line interfaces.
func T(key string, args ...any) string {
	return defaultCatalog.Text(key, args...)
}

// Normalize maps supported locales to Mole's language identifiers.
func Normalize(language string) string {
	language = strings.ToLower(language)
	if language == "ru" || strings.HasPrefix(language, "ru_") || strings.HasPrefix(language, "ru-") {
		return "ru"
	}
	return "en"
}

// Load reads the English catalog and the selected catalog from directory.
func Load(directory, language string) (Catalog, error) {
	english, err := readCatalog(filepath.Join(directory, "en.tsv"))
	if err != nil {
		return Catalog{}, err
	}
	selected := english
	if Normalize(language) == "ru" {
		selected, err = readCatalog(filepath.Join(directory, "ru.tsv"))
		if err != nil {
			return Catalog{}, err
		}
	}
	return Catalog{selected: selected, english: english}, nil
}

// FromEnvironment loads the catalog chosen by the Bash router.
func FromEnvironment() Catalog {
	directory := os.Getenv("MOLE_I18N_DIR")
	if directory == "" {
		directory = findCatalogDirectory()
	}
	catalog, err := Load(directory, os.Getenv("MOLE_LANG"))
	if err != nil {
		return Catalog{}
	}
	return catalog
}

func findCatalogDirectory() string {
	if executable, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(executable), "..", "lib", "i18n")
		if _, err := os.Stat(filepath.Join(candidate, "en.tsv")); err == nil {
			return candidate
		}
	}
	workingDirectory, err := os.Getwd()
	if err != nil {
		return filepath.Join("lib", "i18n")
	}
	for directory := workingDirectory; ; directory = filepath.Dir(directory) {
		candidate := filepath.Join(directory, "lib", "i18n")
		if _, err := os.Stat(filepath.Join(candidate, "en.tsv")); err == nil {
			return candidate
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			break
		}
	}
	return filepath.Join("lib", "i18n")
}

// Text returns a translation, falls back to English, and finally exposes the
// stable key if a caller is missing from both catalogs.
func (catalog Catalog) Text(key string, args ...any) string {
	value, ok := catalog.selected[key]
	if !ok {
		value, ok = catalog.english[key]
	}
	if !ok {
		value = key
	}
	if len(args) > 0 {
		return fmt.Sprintf(value, args...)
	}
	return value
}

func readCatalog(path string) (_ map[string]string, err error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() {
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
	}()

	entries := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		line := scanner.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "\t")
		if !ok || key == "" || value == "" {
			return nil, fmt.Errorf("%s:%d: expected a key and a non-empty value separated by a tab", path, lineNumber)
		}
		if _, duplicate := entries[key]; duplicate {
			return nil, fmt.Errorf("%s:%d: duplicate translation key %q", path, lineNumber, key)
		}
		entries[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return entries, nil
}

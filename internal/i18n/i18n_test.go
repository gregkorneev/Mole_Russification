package i18n

import (
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"strings"
	"testing"
)

func TestNormalize(t *testing.T) {
	tests := map[string]string{
		"ru":          "ru",
		"ru_RU.UTF-8": "ru",
		"ru-RU":       "ru",
		"en":          "en",
		"en_GB":       "en",
		"fr_FR":       "en",
		"":            "en",
	}
	for input, want := range tests {
		if got := Normalize(input); got != want {
			t.Errorf("Normalize(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestCatalogParityAndPlaceholders(t *testing.T) {
	directory := filepath.Join("..", "..", "lib", "i18n")
	english, err := readCatalog(filepath.Join(directory, "en.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	russian, err := readCatalog(filepath.Join(directory, "ru.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(sortedKeys(english), sortedKeys(russian)) {
		t.Fatalf("catalog keys differ: English=%v Russian=%v", sortedKeys(english), sortedKeys(russian))
	}

	placeholder := regexp.MustCompile(`^%[-+# 0]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?[vTtbcdoOqxXUeEfFgGspw]`)
	for key, englishText := range english {
		if en, ru := formatVerbs(placeholder, englishText), formatVerbs(placeholder, russian[key]); !reflect.DeepEqual(en, ru) {
			t.Errorf("placeholder mismatch for %s: English=%v Russian=%v", key, en, ru)
		}
	}
}

func TestRussianCatalogHasNoUnreviewedEnglishFallbacks(t *testing.T) {
	english, err := readCatalog(filepath.Join("..", "..", "lib", "i18n", "en.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	russian, err := readCatalog(filepath.Join("..", "..", "lib", "i18n", "ru.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	allowed := map[string]bool{
		"main_version_macos":                 true, // Product name.
		"main_version_sip":                   true, // macOS security acronym.
		"status_io":                          true, // Standard disk I/O abbreviation.
		"ui_section_time_machine":            true, // Apple product name.
		"analyze_insight_xcode_derived_data": true, // Apple developer directory name.
	}
	for key, value := range english {
		if russian[key] == value && !allowed[key] {
			t.Errorf("Russian translation %s is identical to English: %q", key, value)
		}
	}
}

func formatVerbs(pattern *regexp.Regexp, value string) []string {
	var verbs []string
	for i := 0; i < len(value); {
		if value[i] != '%' {
			i++
			continue
		}
		if i+1 < len(value) && value[i+1] == '%' {
			i += 2
			continue
		}
		if match := pattern.FindString(value[i:]); match != "" {
			verbs = append(verbs, match)
			i += len(match)
			continue
		}
		i++
	}
	return verbs
}

func TestSourceTranslationKeysExistInBothCatalogs(t *testing.T) {
	root := filepath.Join("..", "..")
	english, err := readCatalog(filepath.Join(root, "lib", "i18n", "en.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	russian, err := readCatalog(filepath.Join(root, "lib", "i18n", "ru.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`\bmole_t\s+([a-z][a-z0-9_]*)`),
		regexp.MustCompile(`\bi18n\.T\(\s*"([a-z][a-z0-9_]*)"`),
	}
	var missing []string
	displayLiteral := regexp.MustCompile(`\bmole_display_text "([^"$\\\n]+)"`)
	knownDisplay := make(map[string]bool, len(english))
	var displayTemplates []*regexp.Regexp
	for _, value := range english {
		knownDisplay[value] = true
		if strings.Contains(value, "%s") || strings.Contains(value, "%d") {
			pattern := strings.NewReplacer("%s", ".*", "%d", ".*").Replace(regexp.QuoteMeta(value))
			displayTemplates = append(displayTemplates, regexp.MustCompile("^"+pattern+"$"))
		}
	}
	checkDisplay := func(path string, data []byte) {
		for _, match := range displayLiteral.FindAllSubmatch(data, -1) {
			value := string(match[1])
			if knownDisplay[value] || slices.ContainsFunc(displayTemplates, func(template *regexp.Regexp) bool {
				return template.MatchString(value)
			}) {
				continue
			}
			missing = append(missing, path+": missing display translation for "+value)
		}
	}
	for _, directory := range []string{"bin", "lib", "cmd"} {
		base := filepath.Join(root, directory)
		err := filepath.WalkDir(base, func(path string, entry os.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.IsDir() || strings.HasSuffix(path, "_test.go") {
				return nil
			}
			ext := filepath.Ext(path)
			if ext != ".sh" && ext != ".go" {
				return nil
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			checkDisplay(path, data)
			for _, pattern := range patterns {
				for _, match := range pattern.FindAllSubmatch(data, -1) {
					key := string(match[1])
					if _, ok := english[key]; !ok {
						missing = append(missing, path+": missing English key "+key)
					}
					if _, ok := russian[key]; !ok {
						missing = append(missing, path+": missing Russian key "+key)
					}
				}
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	mainRouter := filepath.Join(root, "mole")
	if data, err := os.ReadFile(mainRouter); err == nil {
		checkDisplay(mainRouter, data)
		pattern := patterns[0]
		for _, match := range pattern.FindAllSubmatch(data, -1) {
			key := string(match[1])
			if _, ok := english[key]; !ok {
				missing = append(missing, mainRouter+": missing English key "+key)
			}
			if _, ok := russian[key]; !ok {
				missing = append(missing, mainRouter+": missing Russian key "+key)
			}
		}
	}
	if len(missing) > 0 {
		t.Fatalf("translation keys missing from catalogs:\n%s", strings.Join(missing, "\n"))
	}
}

func TestCatalogFallbackAndFormatting(t *testing.T) {
	catalog := Catalog{
		selected: map[string]string{"hello": "Привет, %s"},
		english:  map[string]string{"hello": "Hello, %s", "fallback": "Fallback"},
	}
	if got := catalog.Text("hello", "Mole"); got != "Привет, Mole" {
		t.Fatalf("localized formatted text = %q", got)
	}
	if got := catalog.Text("fallback"); got != "Fallback" {
		t.Fatalf("English fallback = %q", got)
	}
	if got := catalog.Text("missing"); got != "missing" {
		t.Fatalf("missing key fallback = %q", got)
	}
}

func TestLoadFallsBackWhenRussianCatalogIsUnavailable(t *testing.T) {
	directory := t.TempDir()
	if err := os.WriteFile(filepath.Join(directory, "en.tsv"), []byte("greeting\tHello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	check := func() {
		t.Helper()
		catalog, err := Load(directory, "ru")
		if err != nil {
			t.Fatal(err)
		}
		if got := catalog.Text("greeting"); got != "Hello" {
			t.Fatalf("fallback = %q, want Hello", got)
		}
	}
	check()
	if err := os.WriteFile(filepath.Join(directory, "ru.tsv"), []byte("greeting\tПривет\ninvalid\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	check()
}

func TestCatalogDirectorySearchFromPackageWorkingDirectory(t *testing.T) {
	packageDirectory := filepath.Join("..", "..", "cmd", "status")
	if got := filepath.Base(findFrom(packageDirectory)); got != "i18n" {
		t.Fatalf("catalog directory = %q", got)
	}
}

func findFrom(directory string) string {
	original, err := os.Getwd()
	if err != nil {
		panic(err)
	}
	if err := os.Chdir(directory); err != nil {
		panic(err)
	}
	defer func() { _ = os.Chdir(original) }()
	return findCatalogDirectory()
}

func sortedKeys(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	return keys
}

// Analyze prints its key hints on one unwrapped line, so a Russian footer much
// wider than the English one loses its last keys (Back, Quit) on a
// standard-width terminal.
func TestRussianAnalyzeControlsStayCloseToEnglishWidth(t *testing.T) {
	english, err := readCatalog(filepath.Join("..", "..", "lib", "i18n", "en.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	russian, err := readCatalog(filepath.Join("..", "..", "lib", "i18n", "ru.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	checked := 0
	for key, value := range english {
		if !strings.HasPrefix(key, "analyze_controls_") {
			continue
		}
		checked++
		en, ru := len([]rune(value)), len([]rune(russian[key]))
		if ru > en+2 {
			t.Errorf("%s: Russian footer is %d columns, English is %d", key, ru, en)
		}
	}
	if checked == 0 {
		t.Fatal("no analyze_controls_ keys found")
	}
}

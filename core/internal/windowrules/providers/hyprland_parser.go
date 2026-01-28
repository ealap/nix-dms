package providers

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/utils"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/windowrules"
)

type HyprlandWindowRule struct {
	MatchClass       string
	MatchTitle       string
	MatchXWayland    *bool
	MatchFloating    *bool
	MatchFullscreen  *bool
	MatchPinned      *bool
	MatchInitialised *bool
	Rule             string
	Value            string
	Source           string
	RawLine          string
}

type HyprlandRulesParser struct {
	configDir        string
	processedFiles   map[string]bool
	rules            []HyprlandWindowRule
	currentSource    string
	dmsRulesExists   bool
	dmsRulesIncluded bool
	includeCount     int
	dmsIncludePos    int
	rulesAfterDMS    int
	dmsProcessed     bool
}

func NewHyprlandRulesParser(configDir string) *HyprlandRulesParser {
	return &HyprlandRulesParser{
		configDir:      configDir,
		processedFiles: make(map[string]bool),
		rules:          []HyprlandWindowRule{},
		dmsIncludePos:  -1,
	}
}

func (p *HyprlandRulesParser) Parse() ([]HyprlandWindowRule, error) {
	expandedDir, err := utils.ExpandPath(p.configDir)
	if err != nil {
		return nil, err
	}

	dmsRulesPath := filepath.Join(expandedDir, "dms", "windowrules.conf")
	if _, err := os.Stat(dmsRulesPath); err == nil {
		p.dmsRulesExists = true
	}

	mainConfig := filepath.Join(expandedDir, "hyprland.conf")
	if err := p.parseFile(mainConfig); err != nil {
		return nil, err
	}

	if p.dmsRulesExists && !p.dmsProcessed {
		p.parseDMSRulesDirectly(dmsRulesPath)
	}

	return p.rules, nil
}

func (p *HyprlandRulesParser) parseDMSRulesDirectly(dmsRulesPath string) {
	data, err := os.ReadFile(dmsRulesPath)
	if err != nil {
		return
	}

	prevSource := p.currentSource
	p.currentSource = dmsRulesPath

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		p.parseLine(line)
	}

	p.currentSource = prevSource
	p.dmsProcessed = true
}

func (p *HyprlandRulesParser) parseFile(filePath string) error {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return err
	}

	if p.processedFiles[absPath] {
		return nil
	}
	p.processedFiles[absPath] = true

	data, err := os.ReadFile(absPath)
	if err != nil {
		return nil
	}

	prevSource := p.currentSource
	p.currentSource = absPath

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "source") {
			p.handleSource(trimmed, filepath.Dir(absPath))
			continue
		}

		p.parseLine(line)
	}

	p.currentSource = prevSource
	return nil
}

func (p *HyprlandRulesParser) handleSource(line string, baseDir string) {
	parts := strings.SplitN(line, "=", 2)
	if len(parts) < 2 {
		return
	}

	sourcePath := strings.TrimSpace(parts[1])
	isDMSSource := sourcePath == "dms/windowrules.conf" || strings.HasSuffix(sourcePath, "/dms/windowrules.conf")

	p.includeCount++
	if isDMSSource {
		p.dmsRulesIncluded = true
		p.dmsIncludePos = p.includeCount
		p.dmsProcessed = true
	}

	fullPath := sourcePath
	if !filepath.IsAbs(sourcePath) {
		fullPath = filepath.Join(baseDir, sourcePath)
	}

	expanded, err := utils.ExpandPath(fullPath)
	if err != nil {
		return
	}

	_ = p.parseFile(expanded)
}

func (p *HyprlandRulesParser) parseLine(line string) {
	trimmed := strings.TrimSpace(line)

	if strings.HasPrefix(trimmed, "windowrule") {
		rule := p.parseWindowRuleLine(trimmed)
		if rule != nil {
			rule.Source = p.currentSource
			p.rules = append(p.rules, *rule)
		}
	}
}

var windowRuleV2Regex = regexp.MustCompile(`^windowrulev?2?\s*=\s*(.+)$`)

func (p *HyprlandRulesParser) parseWindowRuleLine(line string) *HyprlandWindowRule {
	matches := windowRuleV2Regex.FindStringSubmatch(line)
	if len(matches) < 2 {
		return nil
	}

	content := strings.TrimSpace(matches[1])
	isV2 := strings.HasPrefix(line, "windowrulev2")

	rule := &HyprlandWindowRule{
		RawLine: line,
	}

	if isV2 {
		p.parseWindowRuleV2(content, rule)
	} else {
		p.parseWindowRuleV1(content, rule)
	}

	return rule
}

func (p *HyprlandRulesParser) parseWindowRuleV1(content string, rule *HyprlandWindowRule) {
	parts := strings.SplitN(content, ",", 2)
	if len(parts) < 2 {
		return
	}

	rule.Rule = strings.TrimSpace(parts[0])
	rule.MatchClass = strings.TrimSpace(parts[1])
}

func (p *HyprlandRulesParser) parseWindowRuleV2(content string, rule *HyprlandWindowRule) {
	parts := strings.SplitN(content, ",", 2)
	if len(parts) < 2 {
		return
	}

	ruleAndValue := strings.TrimSpace(parts[0])
	matchPart := strings.TrimSpace(parts[1])

	if idx := strings.Index(ruleAndValue, " "); idx > 0 {
		rule.Rule = ruleAndValue[:idx]
		rule.Value = strings.TrimSpace(ruleAndValue[idx+1:])
	} else {
		rule.Rule = ruleAndValue
	}

	matchPairs := strings.Split(matchPart, ",")
	for _, pair := range matchPairs {
		pair = strings.TrimSpace(pair)
		if colonIdx := strings.Index(pair, ":"); colonIdx > 0 {
			key := strings.TrimSpace(pair[:colonIdx])
			value := strings.TrimSpace(pair[colonIdx+1:])

			switch key {
			case "class":
				rule.MatchClass = value
			case "title":
				rule.MatchTitle = value
			case "xwayland":
				b := value == "1" || value == "true"
				rule.MatchXWayland = &b
			case "floating":
				b := value == "1" || value == "true"
				rule.MatchFloating = &b
			case "fullscreen":
				b := value == "1" || value == "true"
				rule.MatchFullscreen = &b
			case "pinned":
				b := value == "1" || value == "true"
				rule.MatchPinned = &b
			case "initialised", "initialized":
				b := value == "1" || value == "true"
				rule.MatchInitialised = &b
			}
		}
	}
}

func (p *HyprlandRulesParser) HasDMSRulesIncluded() bool {
	return p.dmsRulesIncluded
}

func (p *HyprlandRulesParser) buildDMSStatus() *windowrules.DMSRulesStatus {
	status := &windowrules.DMSRulesStatus{
		Exists:          p.dmsRulesExists,
		Included:        p.dmsRulesIncluded,
		IncludePosition: p.dmsIncludePos,
		TotalIncludes:   p.includeCount,
		RulesAfterDMS:   p.rulesAfterDMS,
	}

	switch {
	case !p.dmsRulesExists:
		status.Effective = false
		status.StatusMessage = "dms/windowrules.conf does not exist"
	case !p.dmsRulesIncluded:
		status.Effective = false
		status.StatusMessage = "dms/windowrules.conf is not sourced in config"
	case p.rulesAfterDMS > 0:
		status.Effective = true
		status.OverriddenBy = p.rulesAfterDMS
		status.StatusMessage = "Some DMS rules may be overridden by config rules"
	default:
		status.Effective = true
		status.StatusMessage = "DMS window rules are active"
	}

	return status
}

type HyprlandRulesParseResult struct {
	Rules            []HyprlandWindowRule
	DMSRulesIncluded bool
	DMSStatus        *windowrules.DMSRulesStatus
}

func ParseHyprlandWindowRules(configDir string) (*HyprlandRulesParseResult, error) {
	parser := NewHyprlandRulesParser(configDir)
	rules, err := parser.Parse()
	if err != nil {
		return nil, err
	}
	return &HyprlandRulesParseResult{
		Rules:            rules,
		DMSRulesIncluded: parser.HasDMSRulesIncluded(),
		DMSStatus:        parser.buildDMSStatus(),
	}, nil
}

func applyHyprlandRuleAction(actions *windowrules.Actions, rule, value string) {
	t := true
	switch rule {
	case "float":
		actions.OpenFloating = &t
	case "tile":
		actions.Tile = &t
	case "fullscreen":
		actions.OpenFullscreen = &t
	case "maximize":
		actions.OpenMaximized = &t
	case "nofocus":
		actions.NoFocus = &t
	case "noborder":
		actions.NoBorder = &t
	case "noshadow":
		actions.NoShadow = &t
	case "nodim":
		actions.NoDim = &t
	case "noblur":
		actions.NoBlur = &t
	case "noanim":
		actions.NoAnim = &t
	case "norounding":
		actions.NoRounding = &t
	case "pin":
		actions.Pin = &t
	case "opaque":
		actions.Opaque = &t
	case "forcergbx":
		actions.ForcergbX = &t
	case "opacity":
		if f, err := strconv.ParseFloat(value, 64); err == nil {
			actions.Opacity = &f
		}
	case "size":
		actions.Size = value
	case "move":
		actions.Move = value
	case "monitor":
		actions.Monitor = value
	case "workspace":
		actions.Workspace = value
	case "idleinhibit":
		actions.Idleinhibit = value
	case "rounding":
		if i, err := strconv.Atoi(value); err == nil {
			actions.CornerRadius = &i
		}
	}
}

func ConvertHyprlandRulesToWindowRules(hyprRules []HyprlandWindowRule) []windowrules.WindowRule {
	result := make([]windowrules.WindowRule, 0, len(hyprRules))
	for i, hr := range hyprRules {
		wr := windowrules.WindowRule{
			ID:      strconv.Itoa(i),
			Enabled: true,
			Source:  hr.Source,
			MatchCriteria: windowrules.MatchCriteria{
				AppID:       hr.MatchClass,
				Title:       hr.MatchTitle,
				XWayland:    hr.MatchXWayland,
				IsFloating:  hr.MatchFloating,
				Fullscreen:  hr.MatchFullscreen,
				Pinned:      hr.MatchPinned,
				Initialised: hr.MatchInitialised,
			},
		}
		applyHyprlandRuleAction(&wr.Actions, hr.Rule, hr.Value)
		result = append(result, wr)
	}
	return result
}

type HyprlandWritableProvider struct {
	configDir string
}

func NewHyprlandWritableProvider(configDir string) *HyprlandWritableProvider {
	return &HyprlandWritableProvider{configDir: configDir}
}

func (p *HyprlandWritableProvider) Name() string {
	return "hyprland"
}

func (p *HyprlandWritableProvider) GetOverridePath() string {
	expanded, _ := utils.ExpandPath(p.configDir)
	return filepath.Join(expanded, "dms", "windowrules.conf")
}

func (p *HyprlandWritableProvider) GetRuleSet() (*windowrules.RuleSet, error) {
	result, err := ParseHyprlandWindowRules(p.configDir)
	if err != nil {
		return nil, err
	}
	return &windowrules.RuleSet{
		Title:            "Hyprland Window Rules",
		Provider:         "hyprland",
		Rules:            ConvertHyprlandRulesToWindowRules(result.Rules),
		DMSRulesIncluded: result.DMSRulesIncluded,
		DMSStatus:        result.DMSStatus,
	}, nil
}

func (p *HyprlandWritableProvider) SetRule(rule windowrules.WindowRule) error {
	rules, err := p.LoadDMSRules()
	if err != nil {
		rules = []windowrules.WindowRule{}
	}

	found := false
	for i, r := range rules {
		if r.ID == rule.ID {
			rules[i] = rule
			found = true
			break
		}
	}
	if !found {
		rules = append(rules, rule)
	}

	return p.writeDMSRules(rules)
}

func (p *HyprlandWritableProvider) RemoveRule(id string) error {
	rules, err := p.LoadDMSRules()
	if err != nil {
		return err
	}

	newRules := make([]windowrules.WindowRule, 0, len(rules))
	for _, r := range rules {
		if r.ID != id {
			newRules = append(newRules, r)
		}
	}

	return p.writeDMSRules(newRules)
}

func (p *HyprlandWritableProvider) ReorderRules(ids []string) error {
	rules, err := p.LoadDMSRules()
	if err != nil {
		return err
	}

	ruleMap := make(map[string]windowrules.WindowRule)
	for _, r := range rules {
		ruleMap[r.ID] = r
	}

	newRules := make([]windowrules.WindowRule, 0, len(ids))
	for _, id := range ids {
		if r, ok := ruleMap[id]; ok {
			newRules = append(newRules, r)
			delete(ruleMap, id)
		}
	}

	for _, r := range ruleMap {
		newRules = append(newRules, r)
	}

	return p.writeDMSRules(newRules)
}

var dmsRuleCommentRegex = regexp.MustCompile(`^#\s*DMS-RULE:\s*id=([^,]+),\s*name=(.*)$`)

func (p *HyprlandWritableProvider) LoadDMSRules() ([]windowrules.WindowRule, error) {
	rulesPath := p.GetOverridePath()
	data, err := os.ReadFile(rulesPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []windowrules.WindowRule{}, nil
		}
		return nil, err
	}

	var rules []windowrules.WindowRule
	var currentID, currentName string
	lines := strings.Split(string(data), "\n")

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)

		if matches := dmsRuleCommentRegex.FindStringSubmatch(trimmed); matches != nil {
			currentID = matches[1]
			currentName = matches[2]
			continue
		}

		if strings.HasPrefix(trimmed, "windowrulev2") {
			parser := NewHyprlandRulesParser(p.configDir)
			hrule := parser.parseWindowRuleLine(trimmed)
			if hrule == nil {
				continue
			}

			wr := windowrules.WindowRule{
				ID:      currentID,
				Name:    currentName,
				Enabled: true,
				Source:  rulesPath,
				MatchCriteria: windowrules.MatchCriteria{
					AppID:       hrule.MatchClass,
					Title:       hrule.MatchTitle,
					XWayland:    hrule.MatchXWayland,
					IsFloating:  hrule.MatchFloating,
					Fullscreen:  hrule.MatchFullscreen,
					Pinned:      hrule.MatchPinned,
					Initialised: hrule.MatchInitialised,
				},
			}
			applyHyprlandRuleAction(&wr.Actions, hrule.Rule, hrule.Value)

			if wr.ID == "" {
				wr.ID = hrule.MatchClass
				if wr.ID == "" {
					wr.ID = hrule.MatchTitle
				}
			}

			rules = append(rules, wr)
			currentID = ""
			currentName = ""
		}
	}

	return rules, nil
}

func (p *HyprlandWritableProvider) writeDMSRules(rules []windowrules.WindowRule) error {
	rulesPath := p.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(rulesPath), 0755); err != nil {
		return err
	}

	var lines []string
	lines = append(lines, "# DMS Window Rules - Managed by DankMaterialShell")
	lines = append(lines, "# Do not edit manually - changes may be overwritten")
	lines = append(lines, "")

	for _, rule := range rules {
		lines = append(lines, p.formatRuleLines(rule)...)
	}

	return os.WriteFile(rulesPath, []byte(strings.Join(lines, "\n")), 0644)
}

func (p *HyprlandWritableProvider) formatRuleLines(rule windowrules.WindowRule) []string {
	var lines []string
	lines = append(lines, fmt.Sprintf("# DMS-RULE: id=%s, name=%s", rule.ID, rule.Name))

	var matchParts []string
	if rule.MatchCriteria.AppID != "" {
		matchParts = append(matchParts, fmt.Sprintf("class:%s", rule.MatchCriteria.AppID))
	}
	if rule.MatchCriteria.Title != "" {
		matchParts = append(matchParts, fmt.Sprintf("title:%s", rule.MatchCriteria.Title))
	}
	if rule.MatchCriteria.XWayland != nil {
		matchParts = append(matchParts, fmt.Sprintf("xwayland:%d", boolToInt(*rule.MatchCriteria.XWayland)))
	}
	if rule.MatchCriteria.IsFloating != nil {
		matchParts = append(matchParts, fmt.Sprintf("floating:%d", boolToInt(*rule.MatchCriteria.IsFloating)))
	}
	if rule.MatchCriteria.Fullscreen != nil {
		matchParts = append(matchParts, fmt.Sprintf("fullscreen:%d", boolToInt(*rule.MatchCriteria.Fullscreen)))
	}
	if rule.MatchCriteria.Pinned != nil {
		matchParts = append(matchParts, fmt.Sprintf("pinned:%d", boolToInt(*rule.MatchCriteria.Pinned)))
	}

	matchStr := strings.Join(matchParts, ", ")
	a := rule.Actions

	if a.OpenFloating != nil && *a.OpenFloating {
		lines = append(lines, fmt.Sprintf("windowrulev2 = float, %s", matchStr))
	}
	if a.Tile != nil && *a.Tile {
		lines = append(lines, fmt.Sprintf("windowrulev2 = tile, %s", matchStr))
	}
	if a.OpenFullscreen != nil && *a.OpenFullscreen {
		lines = append(lines, fmt.Sprintf("windowrulev2 = fullscreen, %s", matchStr))
	}
	if a.OpenMaximized != nil && *a.OpenMaximized {
		lines = append(lines, fmt.Sprintf("windowrulev2 = maximize, %s", matchStr))
	}
	if a.NoFocus != nil && *a.NoFocus {
		lines = append(lines, fmt.Sprintf("windowrulev2 = nofocus, %s", matchStr))
	}
	if a.NoBorder != nil && *a.NoBorder {
		lines = append(lines, fmt.Sprintf("windowrulev2 = noborder, %s", matchStr))
	}
	if a.NoShadow != nil && *a.NoShadow {
		lines = append(lines, fmt.Sprintf("windowrulev2 = noshadow, %s", matchStr))
	}
	if a.NoDim != nil && *a.NoDim {
		lines = append(lines, fmt.Sprintf("windowrulev2 = nodim, %s", matchStr))
	}
	if a.NoBlur != nil && *a.NoBlur {
		lines = append(lines, fmt.Sprintf("windowrulev2 = noblur, %s", matchStr))
	}
	if a.NoAnim != nil && *a.NoAnim {
		lines = append(lines, fmt.Sprintf("windowrulev2 = noanim, %s", matchStr))
	}
	if a.NoRounding != nil && *a.NoRounding {
		lines = append(lines, fmt.Sprintf("windowrulev2 = norounding, %s", matchStr))
	}
	if a.Pin != nil && *a.Pin {
		lines = append(lines, fmt.Sprintf("windowrulev2 = pin, %s", matchStr))
	}
	if a.Opaque != nil && *a.Opaque {
		lines = append(lines, fmt.Sprintf("windowrulev2 = opaque, %s", matchStr))
	}
	if a.ForcergbX != nil && *a.ForcergbX {
		lines = append(lines, fmt.Sprintf("windowrulev2 = forcergbx, %s", matchStr))
	}
	if a.Opacity != nil {
		lines = append(lines, fmt.Sprintf("windowrulev2 = opacity %.2f, %s", *a.Opacity, matchStr))
	}
	if a.Size != "" {
		lines = append(lines, fmt.Sprintf("windowrulev2 = size %s, %s", a.Size, matchStr))
	}
	if a.Move != "" {
		lines = append(lines, fmt.Sprintf("windowrulev2 = move %s, %s", a.Move, matchStr))
	}
	if a.Monitor != "" {
		lines = append(lines, fmt.Sprintf("windowrulev2 = monitor %s, %s", a.Monitor, matchStr))
	}
	if a.Workspace != "" {
		lines = append(lines, fmt.Sprintf("windowrulev2 = workspace %s, %s", a.Workspace, matchStr))
	}
	if a.CornerRadius != nil {
		lines = append(lines, fmt.Sprintf("windowrulev2 = rounding %d, %s", *a.CornerRadius, matchStr))
	}
	if a.Idleinhibit != "" {
		lines = append(lines, fmt.Sprintf("windowrulev2 = idleinhibit %s, %s", a.Idleinhibit, matchStr))
	}

	if len(lines) == 1 {
		lines = append(lines, fmt.Sprintf("# (no actions defined for rule %s)", rule.ID))
	}

	lines = append(lines, "")
	return lines
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

package providers

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/keybinds"
	"github.com/AvengeMedia/DankMaterialShell/core/internal/utils"
)

type HyprlandProvider struct {
	configPath       string
	dmsBindsIncluded bool
	parsed           bool
}

func NewHyprlandProvider(configPath string) *HyprlandProvider {
	if configPath == "" {
		configPath = defaultHyprlandConfigDir()
	}
	return &HyprlandProvider{
		configPath: configPath,
	}
}

func defaultHyprlandConfigDir() string {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return ""
	}
	return filepath.Join(configDir, "hypr")
}

func (h *HyprlandProvider) Name() string {
	return "hyprland"
}

func (h *HyprlandProvider) GetCheatSheet() (*keybinds.CheatSheet, error) {
	result, err := ParseHyprlandKeysWithDMS(h.configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse hyprland config: %w", err)
	}

	h.dmsBindsIncluded = result.DMSBindsIncluded
	h.parsed = true

	categorizedBinds := make(map[string][]keybinds.Keybind)
	h.convertSection(result.Section, "", categorizedBinds, result.ConflictingConfigs)

	sheet := &keybinds.CheatSheet{
		Title:            "Hyprland Keybinds",
		Provider:         h.Name(),
		Binds:            categorizedBinds,
		DMSBindsIncluded: result.DMSBindsIncluded,
	}

	if result.DMSStatus != nil {
		sheet.DMSStatus = &keybinds.DMSBindsStatus{
			Exists:          result.DMSStatus.Exists,
			Included:        result.DMSStatus.Included,
			IncludePosition: result.DMSStatus.IncludePosition,
			TotalIncludes:   result.DMSStatus.TotalIncludes,
			BindsAfterDMS:   result.DMSStatus.BindsAfterDMS,
			Effective:       result.DMSStatus.Effective,
			OverriddenBy:    result.DMSStatus.OverriddenBy,
			StatusMessage:   result.DMSStatus.StatusMessage,
		}
	}

	return sheet, nil
}

func (h *HyprlandProvider) HasDMSBindsIncluded() bool {
	if h.parsed {
		return h.dmsBindsIncluded
	}

	result, err := ParseHyprlandKeysWithDMS(h.configPath)
	if err != nil {
		return false
	}

	h.dmsBindsIncluded = result.DMSBindsIncluded
	h.parsed = true
	return h.dmsBindsIncluded
}

func (h *HyprlandProvider) convertSection(section *HyprlandSection, subcategory string, categorizedBinds map[string][]keybinds.Keybind, conflicts map[string]*HyprlandKeyBinding) {
	currentSubcat := subcategory
	if section.Name != "" {
		currentSubcat = section.Name
	}

	for _, kb := range section.Keybinds {
		category := h.categorizeByDispatcher(kb.Dispatcher)
		bind := h.convertKeybind(&kb, currentSubcat, conflicts)
		categorizedBinds[category] = append(categorizedBinds[category], bind)
	}

	for _, child := range section.Children {
		h.convertSection(&child, currentSubcat, categorizedBinds, conflicts)
	}
}

func (h *HyprlandProvider) categorizeByDispatcher(dispatcher string) string {
	switch {
	case strings.Contains(dispatcher, "workspace"):
		return "Workspace"
	case strings.Contains(dispatcher, "monitor"):
		return "Monitor"
	case strings.Contains(dispatcher, "window") ||
		strings.Contains(dispatcher, "focus") ||
		strings.Contains(dispatcher, "move") ||
		strings.Contains(dispatcher, "swap") ||
		strings.Contains(dispatcher, "resize") ||
		dispatcher == "killactive" ||
		dispatcher == "fullscreen" ||
		dispatcher == "togglefloating" ||
		dispatcher == "pin" ||
		dispatcher == "fakefullscreen" ||
		dispatcher == "splitratio" ||
		dispatcher == "resizeactive":
		return "Window"
	case dispatcher == "exec":
		return "Execute"
	case dispatcher == "exit" || strings.Contains(dispatcher, "dpms"):
		return "System"
	default:
		return "Other"
	}
}

func (h *HyprlandProvider) convertKeybind(kb *HyprlandKeyBinding, subcategory string, conflicts map[string]*HyprlandKeyBinding) keybinds.Keybind {
	keyStr := h.formatKey(kb)
	rawAction := h.formatRawAction(kb.Dispatcher, kb.Params)
	desc := kb.Comment

	if desc == "" {
		desc = rawAction
	}

	source := "config"
	if strings.Contains(kb.Source, "dms/binds.conf") {
		source = "dms"
	}

	bind := keybinds.Keybind{
		Key:         keyStr,
		Description: desc,
		Action:      rawAction,
		Subcategory: subcategory,
		Source:      source,
		Flags:       kb.Flags,
	}

	if source == "dms" && conflicts != nil {
		normalizedKey := strings.ToLower(keyStr)
		if conflictKb, ok := conflicts[normalizedKey]; ok {
			bind.Conflict = &keybinds.Keybind{
				Key:         keyStr,
				Description: conflictKb.Comment,
				Action:      h.formatRawAction(conflictKb.Dispatcher, conflictKb.Params),
				Source:      "config",
			}
		}
	}

	return bind
}

func (h *HyprlandProvider) formatRawAction(dispatcher, params string) string {
	if params != "" {
		return dispatcher + " " + params
	}
	return dispatcher
}

func (h *HyprlandProvider) formatKey(kb *HyprlandKeyBinding) string {
	parts := make([]string, 0, len(kb.Mods)+1)
	parts = append(parts, kb.Mods...)
	parts = append(parts, kb.Key)
	return strings.Join(parts, "+")
}

func (h *HyprlandProvider) GetOverridePath() string {
	expanded, err := utils.ExpandPath(h.configPath)
	if err != nil {
		return filepath.Join(h.configPath, "dms", "binds.conf")
	}
	return filepath.Join(expanded, "dms", "binds.conf")
}

func (h *HyprlandProvider) validateAction(action string) error {
	action = strings.TrimSpace(action)
	switch {
	case action == "":
		return fmt.Errorf("action cannot be empty")
	case action == "exec" || action == "exec ":
		return fmt.Errorf("exec dispatcher requires arguments")
	case strings.HasPrefix(action, "exec "):
		rest := strings.TrimSpace(strings.TrimPrefix(action, "exec "))
		if rest == "" {
			return fmt.Errorf("exec dispatcher requires arguments")
		}
	}
	return nil
}

func (h *HyprlandProvider) SetBind(key, action, description string, options map[string]any) error {
	if err := h.validateAction(action); err != nil {
		return err
	}

	overridePath := h.GetOverridePath()

	if err := os.MkdirAll(filepath.Dir(overridePath), 0755); err != nil {
		return fmt.Errorf("failed to create dms directory: %w", err)
	}

	existingBinds, err := h.loadOverrideBinds()
	if err != nil {
		existingBinds = make(map[string]*hyprlandOverrideBind)
	}

	// Extract flags from options
	var flags string
	if options != nil {
		if f, ok := options["flags"].(string); ok {
			flags = f
		}
	}

	normalizedKey := strings.ToLower(key)
	existingBinds[normalizedKey] = &hyprlandOverrideBind{
		Key:         key,
		Action:      action,
		Description: description,
		Flags:       flags,
		Options:     options,
	}

	return h.writeOverrideBinds(existingBinds)
}

func (h *HyprlandProvider) RemoveBind(key string) error {
	existingBinds, err := h.loadOverrideBinds()
	if err != nil {
		return nil
	}

	normalizedKey := strings.ToLower(key)
	delete(existingBinds, normalizedKey)
	return h.writeOverrideBinds(existingBinds)
}

type hyprlandOverrideBind struct {
	Key         string
	Action      string
	Description string
	Flags       string // Bind flags: l=locked, r=release, e=repeat, n=non-consuming, m=mouse, t=transparent, i=ignore-mods, s=separate, d=description, o=long-press
	Options     map[string]any
}

func (h *HyprlandProvider) loadOverrideBinds() (map[string]*hyprlandOverrideBind, error) {
	overridePath := h.GetOverridePath()
	binds := make(map[string]*hyprlandOverrideBind)

	data, err := os.ReadFile(overridePath)
	if os.IsNotExist(err) {
		return binds, nil
	}
	if err != nil {
		return nil, err
	}

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if !strings.HasPrefix(line, "bind") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) < 2 {
			continue
		}

		// Extract flags from bind type
		bindType := strings.TrimSpace(parts[0])
		flags := extractBindFlags(bindType)
		hasDescFlag := strings.Contains(flags, "d")

		content := strings.TrimSpace(parts[1])
		commentParts := strings.SplitN(content, "#", 2)
		bindContent := strings.TrimSpace(commentParts[0])

		var comment string
		if len(commentParts) > 1 {
			comment = strings.TrimSpace(commentParts[1])
		}

		// For bindd, format is: mods, key, description, dispatcher, params
		var minFields, descIndex, dispatcherIndex int
		if hasDescFlag {
			minFields = 4
			descIndex = 2
			dispatcherIndex = 3
		} else {
			minFields = 3
			dispatcherIndex = 2
		}

		fields := strings.SplitN(bindContent, ",", minFields+2)
		if len(fields) < minFields {
			continue
		}

		mods := strings.TrimSpace(fields[0])
		keyName := strings.TrimSpace(fields[1])

		var dispatcher, params string
		if hasDescFlag {
			if comment == "" {
				comment = strings.TrimSpace(fields[descIndex])
			}
			dispatcher = strings.TrimSpace(fields[dispatcherIndex])
			if len(fields) > dispatcherIndex+1 {
				paramParts := fields[dispatcherIndex+1:]
				params = strings.TrimSpace(strings.Join(paramParts, ","))
			}
		} else {
			dispatcher = strings.TrimSpace(fields[dispatcherIndex])
			if len(fields) > dispatcherIndex+1 {
				paramParts := fields[dispatcherIndex+1:]
				params = strings.TrimSpace(strings.Join(paramParts, ","))
			}
		}

		keyStr := h.buildKeyString(mods, keyName)
		normalizedKey := strings.ToLower(keyStr)
		action := dispatcher
		if params != "" {
			action = dispatcher + " " + params
		}

		binds[normalizedKey] = &hyprlandOverrideBind{
			Key:         keyStr,
			Action:      action,
			Description: comment,
			Flags:       flags,
		}
	}

	return binds, nil
}

func (h *HyprlandProvider) buildKeyString(mods, key string) string {
	if mods == "" {
		return key
	}

	modList := strings.FieldsFunc(mods, func(r rune) bool {
		return r == '+' || r == ' '
	})

	parts := append(modList, key)
	return strings.Join(parts, "+")
}

func (h *HyprlandProvider) getBindSortPriority(action string) int {
	switch {
	case strings.HasPrefix(action, "exec") && strings.Contains(action, "dms"):
		return 0
	case strings.Contains(action, "workspace"):
		return 1
	case strings.Contains(action, "window") || strings.Contains(action, "focus") ||
		strings.Contains(action, "move") || strings.Contains(action, "swap") ||
		strings.Contains(action, "resize"):
		return 2
	case strings.Contains(action, "monitor"):
		return 3
	case strings.HasPrefix(action, "exec"):
		return 4
	case action == "exit" || strings.Contains(action, "dpms"):
		return 5
	default:
		return 6
	}
}

func (h *HyprlandProvider) writeOverrideBinds(binds map[string]*hyprlandOverrideBind) error {
	overridePath := h.GetOverridePath()
	content := h.generateBindsContent(binds)
	return os.WriteFile(overridePath, []byte(content), 0644)
}

func (h *HyprlandProvider) generateBindsContent(binds map[string]*hyprlandOverrideBind) string {
	if len(binds) == 0 {
		return ""
	}

	bindList := make([]*hyprlandOverrideBind, 0, len(binds))
	for _, bind := range binds {
		bindList = append(bindList, bind)
	}

	sort.Slice(bindList, func(i, j int) bool {
		pi, pj := h.getBindSortPriority(bindList[i].Action), h.getBindSortPriority(bindList[j].Action)
		if pi != pj {
			return pi < pj
		}
		return bindList[i].Key < bindList[j].Key
	})

	var sb strings.Builder
	for _, bind := range bindList {
		h.writeBindLine(&sb, bind)
	}

	return sb.String()
}

func (h *HyprlandProvider) writeBindLine(sb *strings.Builder, bind *hyprlandOverrideBind) {
	mods, key := h.parseKeyString(bind.Key)
	dispatcher, params := h.parseAction(bind.Action)

	// Write bind type with flags (e.g., "bind", "binde", "bindel")
	sb.WriteString("bind")
	if bind.Flags != "" {
		sb.WriteString(bind.Flags)
	}
	sb.WriteString(" = ")
	sb.WriteString(mods)
	sb.WriteString(", ")
	sb.WriteString(key)
	sb.WriteString(", ")

	// For bindd (description flag), include description before dispatcher
	if strings.Contains(bind.Flags, "d") && bind.Description != "" {
		sb.WriteString(bind.Description)
		sb.WriteString(", ")
	}

	sb.WriteString(dispatcher)

	if params != "" {
		sb.WriteString(", ")
		sb.WriteString(params)
	}

	// Only add comment if not using bindd (which has inline description)
	if bind.Description != "" && !strings.Contains(bind.Flags, "d") {
		sb.WriteString(" # ")
		sb.WriteString(bind.Description)
	}

	sb.WriteString("\n")
}

func (h *HyprlandProvider) parseKeyString(keyStr string) (mods, key string) {
	parts := strings.Split(keyStr, "+")
	switch len(parts) {
	case 0:
		return "", keyStr
	case 1:
		return "", parts[0]
	default:
		return strings.Join(parts[:len(parts)-1], " "), parts[len(parts)-1]
	}
}

func (h *HyprlandProvider) parseAction(action string) (dispatcher, params string) {
	parts := strings.SplitN(action, " ", 2)
	switch len(parts) {
	case 0:
		return action, ""
	case 1:
		dispatcher = parts[0]
	default:
		dispatcher = parts[0]
		params = parts[1]
	}

	// Convert internal spawn format to Hyprland's exec
	if dispatcher == "spawn" {
		dispatcher = "exec"
	}

	return dispatcher, params
}

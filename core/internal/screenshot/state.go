package screenshot

import (
	"encoding/json"
	"os"
	"path"
	"path/filepath"
)

type PersistentState struct {
	LastRegion Region `json:"last_region"`
}

func getStateFilePath() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = path.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(cacheDir, "dms", "screenshot-state.json")
}

func LoadState() (*PersistentState, error) {
	path := getStateFilePath()
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &PersistentState{}, nil
		}
		return nil, err
	}

	var state PersistentState
	if err := json.Unmarshal(data, &state); err != nil {
		return &PersistentState{}, nil
	}
	return &state, nil
}

func SaveState(state *PersistentState) error {
	path := getStateFilePath()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}

func GetLastRegion() Region {
	state, err := LoadState()
	if err != nil {
		return Region{}
	}
	return state.LastRegion
}

func SaveLastRegion(r Region) error {
	state, _ := LoadState()
	state.LastRegion = r
	return SaveState(state)
}

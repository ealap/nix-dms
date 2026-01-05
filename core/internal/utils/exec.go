package utils

import (
	"os/exec"
	"strings"
)

type AppChecker interface {
	CommandExists(cmd string) bool
	AnyCommandExists(cmds ...string) bool
	FlatpakExists(name string) bool
	AnyFlatpakExists(flatpaks ...string) bool
}

type DefaultAppChecker struct{}

func (DefaultAppChecker) CommandExists(cmd string) bool {
	return CommandExists(cmd)
}

func (DefaultAppChecker) AnyCommandExists(cmds ...string) bool {
	return AnyCommandExists(cmds...)
}

func (DefaultAppChecker) FlatpakExists(name string) bool {
	return FlatpakExists(name)
}

func (DefaultAppChecker) AnyFlatpakExists(flatpaks ...string) bool {
	return AnyFlatpakExists(flatpaks...)
}

func CommandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

func AnyCommandExists(cmds ...string) bool {
	for _, cmd := range cmds {
		if CommandExists(cmd) {
			return true
		}
	}
	return false
}

func IsServiceActive(name string, userService bool) bool {
	if !CommandExists("systemctl") {
		return false
	}

	args := []string{"is-active", name}
	if userService {
		args = []string{"--user", "is-active", name}
	}
	output, _ := exec.Command("systemctl", args...).Output()
	return strings.EqualFold(strings.TrimSpace(string(output)), "active")
}

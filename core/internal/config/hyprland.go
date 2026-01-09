package config

import _ "embed"

//go:embed embedded/hyprland.conf
var HyprlandConfig string

//go:embed embedded/hypr-colors.conf
var HyprColorsConfig string

//go:embed embedded/hypr-layout.conf
var HyprLayoutConfig string

//go:embed embedded/hypr-binds.conf
var HyprBindsConfig string

package thememode

import "time"

type Config struct {
	Enabled           bool     `json:"enabled"`
	Mode              string   `json:"mode"`
	StartHour         int      `json:"startHour"`
	StartMinute       int      `json:"startMinute"`
	EndHour           int      `json:"endHour"`
	EndMinute         int      `json:"endMinute"`
	Latitude          *float64 `json:"latitude,omitempty"`
	Longitude         *float64 `json:"longitude,omitempty"`
	UseIPLocation     bool     `json:"useIPLocation"`
	ElevationTwilight float64  `json:"elevationTwilight"`
	ElevationDaylight float64  `json:"elevationDaylight"`
}

type State struct {
	Config         Config    `json:"config"`
	IsLight        bool      `json:"isLight"`
	NextTransition time.Time `json:"nextTransition"`
}

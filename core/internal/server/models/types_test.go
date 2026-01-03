package models

import "testing"

func TestGet(t *testing.T) {
	req := Request{Params: map[string]any{"name": "test", "count": 42, "enabled": true}}

	name, ok := Get[string](req, "name")
	if !ok || name != "test" {
		t.Errorf("Get[string] = %q, %v; want 'test', true", name, ok)
	}

	count, ok := Get[int](req, "count")
	if !ok || count != 42 {
		t.Errorf("Get[int] = %d, %v; want 42, true", count, ok)
	}

	enabled, ok := Get[bool](req, "enabled")
	if !ok || !enabled {
		t.Errorf("Get[bool] = %v, %v; want true, true", enabled, ok)
	}

	_, ok = Get[string](req, "missing")
	if ok {
		t.Error("Get missing key should return false")
	}

	_, ok = Get[int](req, "name")
	if ok {
		t.Error("Get wrong type should return false")
	}
}

func TestGetOr(t *testing.T) {
	req := Request{Params: map[string]any{"name": "test", "enabled": true}}

	if v := GetOr(req, "name", "default"); v != "test" {
		t.Errorf("GetOr existing = %q; want 'test'", v)
	}

	if v := GetOr(req, "missing", "default"); v != "default" {
		t.Errorf("GetOr missing = %q; want 'default'", v)
	}

	if v := GetOr(req, "enabled", false); !v {
		t.Errorf("GetOr bool = %v; want true", v)
	}

	if v := GetOr(req, "name", 0); v != 0 {
		t.Errorf("GetOr wrong type = %d; want 0 (default)", v)
	}
}

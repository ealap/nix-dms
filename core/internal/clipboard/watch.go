package clipboard

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/proto/ext_data_control"
	wlclient "github.com/AvengeMedia/DankMaterialShell/core/pkg/go-wayland/wayland/client"
)

type ClipboardChange struct {
	Data      []byte
	MimeType  string
	MimeTypes []string
}

func Watch(ctx context.Context, callback func(data []byte, mimeType string)) error {
	display, err := wlclient.Connect("")
	if err != nil {
		return fmt.Errorf("wayland connect: %w", err)
	}
	defer display.Destroy()

	wlCtx := display.Context()
	registry, err := display.GetRegistry()
	if err != nil {
		return fmt.Errorf("get registry: %w", err)
	}
	defer registry.Destroy()

	var dataControlMgr *ext_data_control.ExtDataControlManagerV1
	var seat *wlclient.Seat
	var bindErr error

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case "ext_data_control_manager_v1":
			dataControlMgr = ext_data_control.NewExtDataControlManagerV1(wlCtx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, dataControlMgr); err != nil {
				bindErr = err
			}
		case "wl_seat":
			if seat != nil {
				return
			}
			seat = wlclient.NewSeat(wlCtx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, seat); err != nil {
				bindErr = err
			}
		}
	})

	display.Roundtrip()
	display.Roundtrip()

	if bindErr != nil {
		return fmt.Errorf("registry bind: %w", bindErr)
	}

	if dataControlMgr == nil {
		return fmt.Errorf("compositor does not support ext_data_control_manager_v1")
	}
	defer dataControlMgr.Destroy()

	if seat == nil {
		return fmt.Errorf("no seat available")
	}

	device, err := dataControlMgr.GetDataDevice(seat)
	if err != nil {
		return fmt.Errorf("get data device: %w", err)
	}
	defer device.Destroy()

	offerMimeTypes := make(map[*ext_data_control.ExtDataControlOfferV1][]string)

	device.SetDataOfferHandler(func(e ext_data_control.ExtDataControlDeviceV1DataOfferEvent) {
		if e.Id == nil {
			return
		}
		offerMimeTypes[e.Id] = nil
		e.Id.SetOfferHandler(func(me ext_data_control.ExtDataControlOfferV1OfferEvent) {
			offerMimeTypes[e.Id] = append(offerMimeTypes[e.Id], me.MimeType)
		})
	})

	device.SetSelectionHandler(func(e ext_data_control.ExtDataControlDeviceV1SelectionEvent) {
		if e.Id == nil {
			return
		}

		mimes := offerMimeTypes[e.Id]
		selectedMime := selectPreferredMimeType(mimes)
		if selectedMime == "" {
			return
		}

		r, w, err := os.Pipe()
		if err != nil {
			return
		}

		if err := e.Id.Receive(selectedMime, int(w.Fd())); err != nil {
			w.Close()
			r.Close()
			return
		}
		w.Close()

		go func() {
			defer r.Close()
			data, err := io.ReadAll(r)
			if err != nil || len(data) == 0 {
				return
			}
			callback(data, selectedMime)
		}()
	})

	display.Roundtrip()
	display.Roundtrip()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := wlCtx.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
				return fmt.Errorf("set read deadline: %w", err)
			}
			if err := wlCtx.Dispatch(); err != nil {
				if isTimeoutError(err) {
					continue
				}
				return fmt.Errorf("dispatch: %w", err)
			}
		}
	}
}

func WatchAll(ctx context.Context, callback func(data []byte, mimeType string, allMimeTypes []string)) error {
	display, err := wlclient.Connect("")
	if err != nil {
		return fmt.Errorf("wayland connect: %w", err)
	}
	defer display.Destroy()

	wlCtx := display.Context()
	registry, err := display.GetRegistry()
	if err != nil {
		return fmt.Errorf("get registry: %w", err)
	}
	defer registry.Destroy()

	var dataControlMgr *ext_data_control.ExtDataControlManagerV1
	var seat *wlclient.Seat
	var bindErr error

	registry.SetGlobalHandler(func(e wlclient.RegistryGlobalEvent) {
		switch e.Interface {
		case "ext_data_control_manager_v1":
			dataControlMgr = ext_data_control.NewExtDataControlManagerV1(wlCtx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, dataControlMgr); err != nil {
				bindErr = err
			}
		case "wl_seat":
			if seat != nil {
				return
			}
			seat = wlclient.NewSeat(wlCtx)
			if err := registry.Bind(e.Name, e.Interface, e.Version, seat); err != nil {
				bindErr = err
			}
		}
	})

	display.Roundtrip()
	display.Roundtrip()

	if bindErr != nil {
		return fmt.Errorf("registry bind: %w", bindErr)
	}
	if dataControlMgr == nil {
		return fmt.Errorf("compositor does not support ext_data_control_manager_v1")
	}
	defer dataControlMgr.Destroy()
	if seat == nil {
		return fmt.Errorf("no seat available")
	}

	device, err := dataControlMgr.GetDataDevice(seat)
	if err != nil {
		return fmt.Errorf("get data device: %w", err)
	}
	defer device.Destroy()

	offerMimeTypes := make(map[*ext_data_control.ExtDataControlOfferV1][]string)

	device.SetDataOfferHandler(func(e ext_data_control.ExtDataControlDeviceV1DataOfferEvent) {
		if e.Id == nil {
			return
		}
		offerMimeTypes[e.Id] = nil
		e.Id.SetOfferHandler(func(me ext_data_control.ExtDataControlOfferV1OfferEvent) {
			offerMimeTypes[e.Id] = append(offerMimeTypes[e.Id], me.MimeType)
		})
	})

	device.SetSelectionHandler(func(e ext_data_control.ExtDataControlDeviceV1SelectionEvent) {
		if e.Id == nil {
			return
		}

		mimes := offerMimeTypes[e.Id]
		selectedMime := selectPreferredMimeType(mimes)
		if selectedMime == "" {
			return
		}

		mimesCopy := make([]string, len(mimes))
		copy(mimesCopy, mimes)

		r, w, err := os.Pipe()
		if err != nil {
			return
		}

		if err := e.Id.Receive(selectedMime, int(w.Fd())); err != nil {
			w.Close()
			r.Close()
			return
		}
		w.Close()

		go func() {
			defer r.Close()
			data, err := io.ReadAll(r)
			if err != nil || len(data) == 0 {
				return
			}
			callback(data, selectedMime, mimesCopy)
		}()
	})

	display.Roundtrip()
	display.Roundtrip()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := wlCtx.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
				return fmt.Errorf("set read deadline: %w", err)
			}
			if err := wlCtx.Dispatch(); err != nil {
				if isTimeoutError(err) {
					continue
				}
				return fmt.Errorf("dispatch: %w", err)
			}
		}
	}
}

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return true
	}
	if netErr, ok := err.(interface{ Timeout() bool }); ok && netErr.Timeout() {
		return true
	}
	return false
}

func WatchChan(ctx context.Context) (<-chan ClipboardChange, <-chan error) {
	ch := make(chan ClipboardChange, 16)
	errCh := make(chan error, 1)

	go func() {
		defer close(ch)
		err := Watch(ctx, func(data []byte, mimeType string) {
			select {
			case ch <- ClipboardChange{Data: data, MimeType: mimeType}:
			default:
			}
		})
		if err != nil && err != context.Canceled {
			errCh <- err
		}
		close(errCh)
	}()

	time.Sleep(50 * time.Millisecond)
	return ch, errCh
}

package browser

import (
	"net"

	"github.com/AvengeMedia/DankMaterialShell/core/internal/server/models"
)

func HandleRequest(conn net.Conn, req models.Request, manager *Manager) {
	switch req.Method {
	case "browser.open":
		url, ok := models.Get[string](req, "url")
		if !ok {
			models.RespondError(conn, req.ID, "invalid url parameter")
			return
		}
		manager.RequestOpen(url)
		models.Respond(conn, req.ID, "ok")
	default:
		models.RespondError(conn, req.ID, "unknown method")
	}
}

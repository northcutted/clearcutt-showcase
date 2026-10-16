// Command checkout is the showcase's payments service: a small JSON API that
// prices a cart and issues an order ID.
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type line struct {
	SKU      string `json:"sku"`
	Quantity int    `json:"quantity"`
	Cents    int    `json:"cents"`
}

type order struct {
	ID         string `json:"id"`
	Lines      []line `json:"lines"`
	TotalCents int    `json:"totalCents"`
}

func main() {
	r := chi.NewRouter()
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": "checkout"})
	})
	r.Post("/orders", func(w http.ResponseWriter, req *http.Request) {
		var lines []line
		if err := json.NewDecoder(http.MaxBytesReader(w, req.Body, 1<<20)).Decode(&lines); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		o := order{ID: uuid.NewString(), Lines: lines}
		for _, l := range lines {
			o.TotalCents += l.Quantity * l.Cents
		}
		writeJSON(w, http.StatusCreated, o)
	})

	addr := ":" + envOr("PORT", "8080")
	srv := &http.Server{Addr: addr, Handler: r, ReadHeaderTimeout: 5 * time.Second}
	log.Printf("checkout listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

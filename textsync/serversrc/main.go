package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type Entry struct {
	ID      int       `json:"id"`
	Time    time.Time `json:"time"`
	Content string    `json:"content"`
}

var (
	dataFile = "keys.json"
	mu       sync.RWMutex
	entries  []Entry
	nextID   int
)

const maxContentRunes = 65536

var errNoContentField = errors.New("no content field")

func configureDataFileFromEnv() {
	if path := os.Getenv("KEYSERVER_DATA_FILE"); path != "" {
		dataFile = path
	}
}

func load() {
	mu.Lock()
	defer mu.Unlock()

	data, err := os.ReadFile(dataFile)
	if err != nil {
		entries = []Entry{}
		nextID = 0
		return
	}

	if len(data) == 0 {
		entries = []Entry{}
		nextID = 0
		return
	}

	if err := json.Unmarshal(data, &entries); err != nil {
		entries = []Entry{}
		nextID = 0
		return
	}

	if len(entries) > 0 {
		nextID = entries[len(entries)-1].ID + 1
	} else {
		nextID = 0
	}
}

func save() error {
	mu.Lock()
	defer mu.Unlock()

	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return err
	}

	tmpFile := dataFile + ".tmp"
	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return err
	}
	if err := os.Rename(tmpFile, dataFile); err != nil {
		_ = os.Remove(tmpFile)
		return err
	}
	return nil
}

func getEntry(offset int) string {
	mu.RLock()
	defer mu.RUnlock()

	if len(entries) == 0 {
		return ""
	}

	idx := len(entries) - 1 + offset
	if idx < 0 {
		idx = 0
	}
	if idx >= len(entries) {
		idx = len(entries) - 1
	}

	return entries[idx].Content
}

func getByID(id int) string {
	mu.RLock()
	defer mu.RUnlock()

	for _, e := range entries {
		if e.ID == id {
			return e.Content
		}
	}
	if len(entries) > 0 {
		return entries[len(entries)-1].Content
	}
	return ""
}

func listEntries() []map[string]interface{} {
	mu.RLock()
	defer mu.RUnlock()

	list := make([]map[string]interface{}, len(entries))
	for i, e := range entries {
		list[i] = map[string]interface{}{
			"id":      e.ID,
			"time":    e.Time.Format(time.RFC3339),
			"content": e.Content,
		}
	}
	return list
}

func firstContentField(values map[string][]string) (string, bool) {
	for _, key := range []string{"content", "text", "body", "value", "input"} {
		if vals, ok := values[key]; ok && len(vals) > 0 {
			return vals[0], true
		}
	}

	if len(values) == 1 {
		for _, vals := range values {
			if len(vals) > 0 && vals[0] != "" {
				return vals[0], true
			}
		}
	}

	return "", false
}

func contentFromJSON(body []byte) (string, error) {
	var text string
	if err := json.Unmarshal(body, &text); err == nil {
		return text, nil
	}

	var obj map[string]interface{}
	if err := json.Unmarshal(body, &obj); err != nil {
		return "", err
	}

	for _, key := range []string{"content", "text", "body", "value", "input"} {
		if value, ok := obj[key]; ok {
			if s, ok := value.(string); ok {
				return s, nil
			}
		}
	}

	if len(obj) == 1 {
		for _, value := range obj {
			if s, ok := value.(string); ok {
				return s, nil
			}
		}
	}

	return "", errNoContentField
}

func contentFromMultipart(body []byte, boundary string) (string, error) {
	form, err := multipart.NewReader(bytes.NewReader(body), boundary).ReadForm(int64(len(body)))
	if err != nil {
		return "", err
	}
	defer form.RemoveAll()

	if content, ok := firstContentField(form.Value); ok {
		return content, nil
	}

	return "", errNoContentField
}

func postContent(r *http.Request, body []byte) (string, error) {
	contentType := r.Header.Get("Content-Type")
	mediaType, params, err := mime.ParseMediaType(contentType)
	if err != nil {
		mediaType = ""
	}

	switch mediaType {
	case "application/json":
		return contentFromJSON(body)
	case "application/x-www-form-urlencoded":
		values, err := url.ParseQuery(string(body))
		if err != nil {
			return "", err
		}
		if content, ok := firstContentField(values); ok {
			return content, nil
		}
		raw := string(body)
		if strings.Contains(raw, "%") {
			if decoded, err := url.QueryUnescape(raw); err == nil {
				return decoded, nil
			}
		}
		return raw, nil
	case "multipart/form-data":
		boundary := params["boundary"]
		if boundary == "" {
			return "", errNoContentField
		}
		return contentFromMultipart(body, boundary)
	default:
		return string(body), nil
	}
}

func handler(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/":
		http.ServeFile(w, r, "index.html")
		return

	case "/api/get":
		offset := 0
		if q := r.URL.Query().Get("offset"); q != "" {
			if v, err := strconv.Atoi(q); err == nil {
				offset = v
			}
		}
		if idStr := r.URL.Query().Get("id"); idStr != "" {
			if id, err := strconv.Atoi(idStr); err == nil {
				w.Header().Set("Content-Type", "text/plain; charset=utf-8")
				w.Write([]byte(getByID(id)))
				return
			}
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte(getEntry(offset)))

	case "/api/post":
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read error", http.StatusBadRequest)
			return
		}

		content, err := postContent(r, body)
		if err != nil {
			http.Error(w, "invalid content", http.StatusBadRequest)
			return
		}
		if content == "" {
			http.Error(w, "empty", http.StatusBadRequest)
			return
		}

		// UTF-8 验证与清理，支持中文、英文、数字等所有字符
		if !utf8.ValidString(content) {
			content = "invalid utf8"
		}

		// Keep large pasted text intact; reject oversize input instead of silently truncating it.
		if utf8.RuneCountInString(content) > maxContentRunes {
			http.Error(w, "too large", http.StatusRequestEntityTooLarge)
			return
		}

		mu.Lock()
		entry := Entry{
			ID:      nextID,
			Time:    time.Now(),
			Content: content,
		}
		entries = append(entries, entry)
		nextID++
		mu.Unlock()

		if err := save(); err != nil {
			http.Error(w, "save error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("ok"))

	case "/api/list":
		list := listEntries()
		data, _ := json.Marshal(list)
		w.Header().Set("Content-Type", "application/json")
		w.Write(data)

	default:
		http.NotFound(w, r)
	}
}

func main() {
	configureDataFileFromEnv()
	load()

	http.HandleFunc("/", handler)

	fmt.Println("Key exchange server starting on :8080")
	fmt.Println("Endpoints:")
	fmt.Println("  GET  /api/get          -> latest")
	fmt.Println("  GET  /api/get?offset=-1 -> previous")
	fmt.Println("  GET  /api/get?id=5     -> specific id")
	fmt.Println("  POST /api/post         -> body as new key")
	fmt.Println("  GET  /api/list         -> list all with time & id")

	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Println("Server error:", err)
	}
}

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type Entry struct {
	ID           int       `json:"id"`
	Time         time.Time `json:"time"`
	Content      string    `json:"content"`
	Kind         string    `json:"kind,omitempty"`
	MimeType     string    `json:"mime_type,omitempty"`
	AssetID      string    `json:"asset_id,omitempty"`
	AssetURL     string    `json:"asset_url,omitempty"`
	ThumbnailID  string    `json:"thumbnail_id,omitempty"`
	ThumbnailURL string    `json:"thumbnail_url,omitempty"`
	FileName     string    `json:"file_name,omitempty"`
	Width        int       `json:"width,omitempty"`
	Height       int       `json:"height,omitempty"`
	ByteCount    int       `json:"byte_count,omitempty"`
}

var (
	dataFile = "keys.json"
	mu       sync.RWMutex
	entries  []Entry
	nextID   int
)

const maxContentRunes = 65536
const maxImageBytes = 8 * 1024 * 1024
const thumbnailMaxSide = 360

var errNoContentField = errors.New("no content field")

func configureDataFileFromEnv() {
	if path := os.Getenv("KEYSERVER_DATA_FILE"); path != "" {
		dataFile = path
	}
}

func assetDir() string {
	if path := os.Getenv("KEYSERVER_ASSET_DIR"); path != "" {
		return path
	}
	return filepath.Join(filepath.Dir(dataFile), "assets")
}

func withAssetURLs(entry Entry) Entry {
	if entry.Kind == "" {
		entry.Kind = "text"
	}
	if entry.AssetID != "" {
		entry.AssetURL = "/api/assets/" + entry.AssetID
	}
	if entry.ThumbnailID != "" {
		entry.ThumbnailURL = "/api/assets/" + entry.ThumbnailID
	}
	return entry
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

func latestEntry() *Entry {
	mu.RLock()
	defer mu.RUnlock()

	if len(entries) == 0 {
		return nil
	}
	entry := withAssetURLs(entries[len(entries)-1])
	return &entry
}

func listEntries() []map[string]interface{} {
	mu.RLock()
	defer mu.RUnlock()

	list := make([]map[string]interface{}, len(entries))
	for i, e := range entries {
		e = withAssetURLs(e)
		list[i] = map[string]interface{}{
			"id":            e.ID,
			"time":          e.Time.Format(time.RFC3339),
			"content":       e.Content,
			"kind":          e.Kind,
			"mime_type":     e.MimeType,
			"asset_id":      e.AssetID,
			"asset_url":     e.AssetURL,
			"thumbnail_id":  e.ThumbnailID,
			"thumbnail_url": e.ThumbnailURL,
			"file_name":     e.FileName,
			"width":         e.Width,
			"height":        e.Height,
			"byte_count":    e.ByteCount,
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

func nextEntryID() int {
	mu.Lock()
	defer mu.Unlock()

	id := nextID
	nextID++
	return id
}

func appendEntry(entry Entry) error {
	mu.Lock()
	entries = append(entries, entry)
	mu.Unlock()
	return save()
}

func postTextEntry(content string) error {
	if content == "" {
		return errNoContentField
	}

	if !utf8.ValidString(content) {
		content = "invalid utf8"
	}

	if utf8.RuneCountInString(content) > maxContentRunes {
		return http.ErrContentLength
	}

	entry := Entry{
		ID:      nextEntryID(),
		Time:    time.Now(),
		Content: content,
		Kind:    "text",
	}
	return appendEntry(entry)
}

func postImageEntry(upload *uploadedImage) error {
	entry, err := storeImageAsset(upload, nextEntryID())
	if err != nil {
		return err
	}
	return appendEntry(entry)
}

type uploadedImage struct {
	data     []byte
	mimeType string
	fileName string
	width    int
	height   int
}

func imageFromMultipart(r *http.Request, body []byte, boundary string) (*uploadedImage, string, error) {
	form, err := multipart.NewReader(bytes.NewReader(body), boundary).ReadForm(int64(maxImageBytes + 1024*1024))
	if err != nil {
		return nil, "", err
	}
	defer form.RemoveAll()

	for _, key := range []string{"image", "file", "asset"} {
		files := form.File[key]
		if len(files) == 0 {
			continue
		}
		fileHeader := files[0]
		if fileHeader.Size > maxImageBytes {
			return nil, "", http.ErrContentLength
		}
		file, err := fileHeader.Open()
		if err != nil {
			return nil, "", err
		}
		defer file.Close()

		data, err := io.ReadAll(io.LimitReader(file, maxImageBytes+1))
		if err != nil {
			return nil, "", err
		}
		if len(data) > maxImageBytes {
			return nil, "", http.ErrContentLength
		}

		mimeType := fileHeader.Header.Get("Content-Type")
		if mimeType == "" {
			mimeType = http.DetectContentType(data)
		}
		image, err := decodeUploadedImage(data, mimeType, fileHeader.Filename)
		if err != nil {
			return nil, "", err
		}
		return image, "", nil
	}

	if content, ok := firstContentField(form.Value); ok {
		return nil, content, nil
	}

	return nil, "", errNoContentField
}

func decodeUploadedImage(data []byte, mimeType string, fileName string) (*uploadedImage, error) {
	if len(data) == 0 {
		return nil, errNoContentField
	}
	if len(data) > maxImageBytes {
		return nil, http.ErrContentLength
	}

	config, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	if config.Width <= 0 || config.Height <= 0 {
		return nil, errors.New("invalid image dimensions")
	}

	normalizedMime := normalizedImageMimeType(mimeType, format)
	if normalizedMime == "" {
		return nil, errors.New("unsupported image type")
	}

	return &uploadedImage{
		data:     data,
		mimeType: normalizedMime,
		fileName: safeFileName(fileName, extensionForMimeType(normalizedMime)),
		width:    config.Width,
		height:   config.Height,
	}, nil
}

func normalizedImageMimeType(mimeType string, format string) string {
	switch strings.ToLower(strings.TrimSpace(mimeType)) {
	case "image/png", "image/jpeg", "image/jpg", "image/gif":
		if strings.EqualFold(mimeType, "image/jpg") {
			return "image/jpeg"
		}
		return strings.ToLower(strings.TrimSpace(mimeType))
	}

	switch strings.ToLower(format) {
	case "png":
		return "image/png"
	case "jpeg", "jpg":
		return "image/jpeg"
	case "gif":
		return "image/gif"
	default:
		return ""
	}
}

func extensionForMimeType(mimeType string) string {
	switch mimeType {
	case "image/png":
		return "png"
	case "image/jpeg":
		return "jpg"
	case "image/gif":
		return "gif"
	default:
		return "img"
	}
}

func safeFileName(fileName string, fallbackExtension string) string {
	name := filepath.Base(strings.TrimSpace(fileName))
	if name == "." || name == "/" || name == "" {
		return "clipboard." + fallbackExtension
	}
	name = strings.Map(func(r rune) rune {
		if r == '/' || r == '\\' || r == ':' || r == 0 {
			return '_'
		}
		return r
	}, name)
	if filepath.Ext(name) == "" {
		name += "." + fallbackExtension
	}
	return name
}

func storeImageAsset(upload *uploadedImage, id int) (Entry, error) {
	root := assetDir()
	thumbDir := filepath.Join(root, "thumbs")
	if err := os.MkdirAll(root, 0755); err != nil {
		return Entry{}, err
	}
	if err := os.MkdirAll(thumbDir, 0755); err != nil {
		return Entry{}, err
	}

	extension := extensionForMimeType(upload.mimeType)
	assetID := fmt.Sprintf("%d-%d.%s", id, time.Now().UnixNano(), extension)
	thumbnailID := "thumbs/" + fmt.Sprintf("%d-%d.jpg", id, time.Now().UnixNano())
	assetPath := filepath.Join(root, assetID)
	thumbnailPath := filepath.Join(root, thumbnailID)

	if err := os.WriteFile(assetPath, upload.data, 0644); err != nil {
		return Entry{}, err
	}
	thumbnail, err := makeJPEGThumbnail(upload.data)
	if err != nil {
		_ = os.Remove(assetPath)
		return Entry{}, err
	}
	if err := os.WriteFile(thumbnailPath, thumbnail, 0644); err != nil {
		_ = os.Remove(assetPath)
		return Entry{}, err
	}

	content := fmt.Sprintf("图片 %s (%d×%d)", upload.fileName, upload.width, upload.height)
	return Entry{
		ID:          id,
		Time:        time.Now(),
		Content:     content,
		Kind:        "image",
		MimeType:    upload.mimeType,
		AssetID:     assetID,
		ThumbnailID: thumbnailID,
		FileName:    upload.fileName,
		Width:       upload.width,
		Height:      upload.height,
		ByteCount:   len(upload.data),
	}, nil
}

func makeJPEGThumbnail(data []byte) ([]byte, error) {
	source, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	bounds := source.Bounds()
	width := bounds.Dx()
	height := bounds.Dy()
	if width <= 0 || height <= 0 {
		return nil, errors.New("invalid thumbnail dimensions")
	}

	scale := float64(thumbnailMaxSide) / float64(max(width, height))
	if scale > 1 {
		scale = 1
	}
	thumbWidth := max(1, int(float64(width)*scale))
	thumbHeight := max(1, int(float64(height)*scale))
	destination := image.NewRGBA(image.Rect(0, 0, thumbWidth, thumbHeight))
	for y := 0; y < thumbHeight; y++ {
		sourceY := bounds.Min.Y + y*height/thumbHeight
		for x := 0; x < thumbWidth; x++ {
			sourceX := bounds.Min.X + x*width/thumbWidth
			destination.Set(x, y, source.At(sourceX, sourceY))
		}
	}

	var out bytes.Buffer
	if err := jpeg.Encode(&out, destination, &jpeg.Options{Quality: 82}); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

func max(a int, b int) int {
	if a > b {
		return a
	}
	return b
}

func handler(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(r.URL.Path, "/api/assets/") {
		serveAsset(w, r)
		return
	}

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
		handlePostText(w, r)

	case "/api/list":
		list := listEntries()
		data, _ := json.Marshal(list)
		w.Header().Set("Content-Type", "application/json")
		w.Write(data)

	case "/api/items":
		switch r.Method {
		case http.MethodGet:
			list := listEntries()
			data, _ := json.Marshal(list)
			w.Header().Set("Content-Type", "application/json")
			w.Write(data)
		case http.MethodPost:
			handlePostItem(w, r)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}

	case "/api/items/latest":
		entry := latestEntry()
		if entry == nil {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		data, _ := json.Marshal(entry)
		w.Header().Set("Content-Type", "application/json")
		w.Write(data)

	default:
		http.NotFound(w, r)
	}
}

func handlePostText(w http.ResponseWriter, r *http.Request) {
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

	if err := postTextEntry(content); err != nil {
		writePostError(w, err)
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte("ok"))
}

func handlePostItem(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, maxImageBytes+1024*1024))
	if err != nil {
		http.Error(w, "read error", http.StatusBadRequest)
		return
	}

	contentType := r.Header.Get("Content-Type")
	mediaType, params, err := mime.ParseMediaType(contentType)
	if err != nil {
		mediaType = ""
	}

	if mediaType == "multipart/form-data" {
		boundary := params["boundary"]
		if boundary == "" {
			http.Error(w, "invalid content", http.StatusBadRequest)
			return
		}

		image, content, err := imageFromMultipart(r, body, boundary)
		if err != nil {
			if errors.Is(err, http.ErrContentLength) {
				http.Error(w, "too large", http.StatusRequestEntityTooLarge)
			} else {
				http.Error(w, "invalid content", http.StatusBadRequest)
			}
			return
		}
		if image != nil {
			if err := postImageEntry(image); err != nil {
				writePostError(w, err)
				return
			}
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			w.Write([]byte("ok"))
			return
		}
		if content != "" {
			if err := postTextEntry(content); err != nil {
				writePostError(w, err)
				return
			}
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			w.Write([]byte("ok"))
			return
		}
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
	if err := postTextEntry(content); err != nil {
		writePostError(w, err)
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write([]byte("ok"))
}

func writePostError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, http.ErrContentLength):
		http.Error(w, "too large", http.StatusRequestEntityTooLarge)
	case errors.Is(err, errNoContentField):
		http.Error(w, "empty", http.StatusBadRequest)
	default:
		http.Error(w, "save error", http.StatusInternalServerError)
	}
}

func serveAsset(w http.ResponseWriter, r *http.Request) {
	assetID := strings.TrimPrefix(r.URL.Path, "/api/assets/")
	cleanID := filepath.Clean(assetID)
	if cleanID == "." || strings.HasPrefix(cleanID, "..") || filepath.IsAbs(cleanID) {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, filepath.Join(assetDir(), cleanID))
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

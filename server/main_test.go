package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func resetTestState(t *testing.T) {
	t.Helper()

	mu.Lock()
	entries = nil
	nextID = 0
	mu.Unlock()

	dataFile = filepath.Join(t.TempDir(), "keys.json")
	if err := os.WriteFile(dataFile, []byte("[]"), 0644); err != nil {
		t.Fatalf("write temp data file: %v", err)
	}
}

func TestPostPreservesMultilineContent(t *testing.T) {
	resetTestState(t)

	content := "第一行\nsecond line\nthird line with spaces  "
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	getReq := httptest.NewRequest(http.MethodGet, "/api/get", nil)
	getRec := httptest.NewRecorder()
	handler(getRec, getReq)

	if got := getRec.Body.String(); got != content {
		t.Fatalf("stored content mismatch\n got: %q\nwant: %q", got, content)
	}
}

func TestPostAcceptsFormEncodedShortcutContent(t *testing.T) {
	resetTestState(t)

	content := "第一行\nsecond line\nthird+line"
	form := url.Values{}
	form.Set("content", content)
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	if got := getEntry(0); got != content {
		t.Fatalf("stored form content mismatch\n got: %q\nwant: %q", got, content)
	}
}

func TestPostAcceptsPlainTextWithFormContentType(t *testing.T) {
	resetTestState(t)

	content := "第一行%0Asecond line%0Athird line"
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	if got, want := getEntry(0), "第一行\nsecond line\nthird line"; got != want {
		t.Fatalf("stored fallback form content mismatch\n got: %q\nwant: %q", got, want)
	}
}

func TestPostAcceptsJSONShortcutContent(t *testing.T) {
	resetTestState(t)

	content := "第一行\nsecond line\nthird line"
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(`{"text":"`+strings.ReplaceAll(content, "\n", `\n`)+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	if got := getEntry(0); got != content {
		t.Fatalf("stored json content mismatch\n got: %q\nwant: %q", got, content)
	}
}

func TestPostAcceptsMultipartShortcutContent(t *testing.T) {
	resetTestState(t)

	content := "第一行\nsecond line\nthird line"
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	if err := writer.WriteField("content", content); err != nil {
		t.Fatalf("write multipart field: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/post", &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	if got := getEntry(0); got != content {
		t.Fatalf("stored multipart content mismatch\n got: %q\nwant: %q", got, content)
	}
}

func TestPostItemsAcceptsImageAndCreatesThumbnail(t *testing.T) {
	resetTestState(t)

	var imageData bytes.Buffer
	img := image.NewRGBA(image.Rect(0, 0, 16, 10))
	for y := 0; y < 10; y++ {
		for x := 0; x < 16; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 10), G: uint8(y * 20), B: 120, A: 255})
		}
	}
	if err := png.Encode(&imageData, img); err != nil {
		t.Fatalf("encode png: %v", err)
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("image", "sample.png")
	if err != nil {
		t.Fatalf("create image field: %v", err)
	}
	if _, err := part.Write(imageData.Bytes()); err != nil {
		t.Fatalf("write image field: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/items", &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/items", nil)
	listRec := httptest.NewRecorder()
	handler(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list status = %d, want %d", listRec.Code, http.StatusOK)
	}

	var items []map[string]interface{}
	if err := json.Unmarshal(listRec.Body.Bytes(), &items); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("items length = %d, want 1", len(items))
	}
	if got := items[0]["kind"]; got != "image" {
		t.Fatalf("kind = %v, want image", got)
	}
	if got := items[0]["mime_type"]; got != "image/png" {
		t.Fatalf("mime_type = %v, want image/png", got)
	}
	if got := int(items[0]["width"].(float64)); got != 16 {
		t.Fatalf("width = %d, want 16", got)
	}
	if got := int(items[0]["height"].(float64)); got != 10 {
		t.Fatalf("height = %d, want 10", got)
	}

	thumbnailURL, ok := items[0]["thumbnail_url"].(string)
	if !ok || thumbnailURL == "" {
		t.Fatalf("thumbnail_url missing: %#v", items[0])
	}
	thumbReq := httptest.NewRequest(http.MethodGet, thumbnailURL, nil)
	thumbRec := httptest.NewRecorder()
	handler(thumbRec, thumbReq)
	if thumbRec.Code != http.StatusOK {
		t.Fatalf("thumbnail status = %d, want %d", thumbRec.Code, http.StatusOK)
	}
	if _, _, err := image.Decode(bytes.NewReader(thumbRec.Body.Bytes())); err != nil {
		t.Fatalf("decode thumbnail: %v", err)
	}
}

func TestDeleteMovesEntryToTrashAndRestore(t *testing.T) {
	resetTestState(t)

	for _, content := range []string{"https://example.com", "普通文本"} {
		req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
		rec := httptest.NewRecorder()
		handler(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
		}
	}

	linkReq := httptest.NewRequest(http.MethodGet, "/api/items?category=link", nil)
	linkRec := httptest.NewRecorder()
	handler(linkRec, linkReq)
	if linkRec.Code != http.StatusOK {
		t.Fatalf("link list status = %d, want %d", linkRec.Code, http.StatusOK)
	}
	var linkItems []map[string]interface{}
	if err := json.Unmarshal(linkRec.Body.Bytes(), &linkItems); err != nil {
		t.Fatalf("decode link list: %v", err)
	}
	if len(linkItems) != 1 || linkItems[0]["category"] != "link" {
		t.Fatalf("link category list mismatch: %#v", linkItems)
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/api/items/0", nil)
	deleteRec := httptest.NewRecorder()
	handler(deleteRec, deleteReq)
	if deleteRec.Code != http.StatusOK {
		t.Fatalf("delete status = %d, want %d: %s", deleteRec.Code, http.StatusOK, deleteRec.Body.String())
	}

	listReq := httptest.NewRequest(http.MethodGet, "/api/items", nil)
	listRec := httptest.NewRecorder()
	handler(listRec, listReq)
	var activeItems []map[string]interface{}
	if err := json.Unmarshal(listRec.Body.Bytes(), &activeItems); err != nil {
		t.Fatalf("decode active list: %v", err)
	}
	if len(activeItems) != 1 || int(activeItems[0]["id"].(float64)) != 1 {
		t.Fatalf("active list after delete mismatch: %#v", activeItems)
	}

	trashReq := httptest.NewRequest(http.MethodGet, "/api/trash", nil)
	trashRec := httptest.NewRecorder()
	handler(trashRec, trashReq)
	var trashItems []map[string]interface{}
	if err := json.Unmarshal(trashRec.Body.Bytes(), &trashItems); err != nil {
		t.Fatalf("decode trash list: %v", err)
	}
	if len(trashItems) != 1 || int(trashItems[0]["id"].(float64)) != 0 || trashItems[0]["deleted_at"] == nil {
		t.Fatalf("trash list mismatch: %#v", trashItems)
	}

	restoreReq := httptest.NewRequest(http.MethodPost, "/api/items/0/restore", nil)
	restoreRec := httptest.NewRecorder()
	handler(restoreRec, restoreReq)
	if restoreRec.Code != http.StatusOK {
		t.Fatalf("restore status = %d, want %d: %s", restoreRec.Code, http.StatusOK, restoreRec.Body.String())
	}

	restoredReq := httptest.NewRequest(http.MethodGet, "/api/items", nil)
	restoredRec := httptest.NewRecorder()
	handler(restoredRec, restoredReq)
	var restoredItems []map[string]interface{}
	if err := json.Unmarshal(restoredRec.Body.Bytes(), &restoredItems); err != nil {
		t.Fatalf("decode restored list: %v", err)
	}
	if len(restoredItems) != 2 {
		t.Fatalf("restored list length = %d, want 2", len(restoredItems))
	}

	permanentReq := httptest.NewRequest(http.MethodDelete, "/api/items/0/permanent", nil)
	permanentRec := httptest.NewRecorder()
	handler(permanentRec, permanentReq)
	if permanentRec.Code != http.StatusOK {
		t.Fatalf("permanent delete status = %d, want %d: %s", permanentRec.Code, http.StatusOK, permanentRec.Body.String())
	}

	allReq := httptest.NewRequest(http.MethodGet, "/api/items?include_deleted=1", nil)
	allRec := httptest.NewRecorder()
	handler(allRec, allReq)
	var allItems []map[string]interface{}
	if err := json.Unmarshal(allRec.Body.Bytes(), &allItems); err != nil {
		t.Fatalf("decode all list: %v", err)
	}
	if len(allItems) != 1 || int(allItems[0]["id"].(float64)) != 1 {
		t.Fatalf("all list after permanent delete mismatch: %#v", allItems)
	}
}

func TestPermanentlyDeleteTrash(t *testing.T) {
	resetTestState(t)

	for _, content := range []string{"one", "two", "three"} {
		req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
		rec := httptest.NewRecorder()
		handler(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
		}
	}

	for _, id := range []int{0, 2} {
		req := httptest.NewRequest(http.MethodDelete, fmt.Sprintf("/api/items/%d", id), nil)
		rec := httptest.NewRecorder()
		handler(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("delete %d status = %d, want %d: %s", id, rec.Code, http.StatusOK, rec.Body.String())
		}
	}

	req := httptest.NewRequest(http.MethodDelete, "/api/trash/permanent", nil)
	rec := httptest.NewRecorder()
	handler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete trash status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}
	var result map[string]int
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode delete trash result: %v", err)
	}
	if result["deleted"] != 2 {
		t.Fatalf("deleted count = %d, want 2", result["deleted"])
	}

	trashReq := httptest.NewRequest(http.MethodGet, "/api/trash", nil)
	trashRec := httptest.NewRecorder()
	handler(trashRec, trashReq)
	var trashItems []map[string]interface{}
	if err := json.Unmarshal(trashRec.Body.Bytes(), &trashItems); err != nil {
		t.Fatalf("decode trash list: %v", err)
	}
	if len(trashItems) != 0 {
		t.Fatalf("trash list length = %d, want 0: %#v", len(trashItems), trashItems)
	}

	allReq := httptest.NewRequest(http.MethodGet, "/api/items?include_deleted=1", nil)
	allRec := httptest.NewRecorder()
	handler(allRec, allReq)
	var allItems []map[string]interface{}
	if err := json.Unmarshal(allRec.Body.Bytes(), &allItems); err != nil {
		t.Fatalf("decode all list: %v", err)
	}
	if len(allItems) != 1 || int(allItems[0]["id"].(float64)) != 1 {
		t.Fatalf("all list after delete trash mismatch: %#v", allItems)
	}
}

func TestPostDoesNotTruncateAfter128Runes(t *testing.T) {
	resetTestState(t)

	content := strings.Repeat("中", 129) + "\n" + strings.Repeat("x", 129)
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("post status = %d, want %d: %s", rec.Code, http.StatusOK, rec.Body.String())
	}

	if got := getEntry(0); got != content {
		t.Fatalf("content was truncated\n got runes: %d\nwant runes: %d", len([]rune(got)), len([]rune(content)))
	}
}

func TestPostRejectsOversizeContent(t *testing.T) {
	resetTestState(t)

	content := strings.Repeat("a", maxContentRunes+1)
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader(content))
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("post status = %d, want %d", rec.Code, http.StatusRequestEntityTooLarge)
	}
}

func TestConfigureDataFileFromEnv(t *testing.T) {
	original := dataFile
	t.Cleanup(func() {
		dataFile = original
	})

	path := filepath.Join(t.TempDir(), "custom.json")
	t.Setenv("KEYSERVER_DATA_FILE", path)

	configureDataFileFromEnv()

	if dataFile != path {
		t.Fatalf("dataFile = %q, want %q", dataFile, path)
	}
}

func TestPostReportsSaveError(t *testing.T) {
	resetTestState(t)

	dataFile = filepath.Join(t.TempDir(), "missing", "keys.json")
	req := httptest.NewRequest(http.MethodPost, "/api/post", strings.NewReader("content"))
	rec := httptest.NewRecorder()

	handler(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("post status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

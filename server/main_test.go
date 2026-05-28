package main

import (
	"bytes"
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

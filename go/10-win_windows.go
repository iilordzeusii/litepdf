//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"

	"github.com/jchv/go-webview2"
)

func showWindow(url string) {
	data := filepath.Join(os.Getenv("LOCALAPPDATA"), "LitePDF")
	w := webview2.NewWithOptions(webview2.WebViewOptions{DataPath: data, WindowOptions: webview2.WindowOptions{Title: "LitePDF", Width: 1280, Height: 860, Center: true}})
	if w == nil { // WebView2 runtime missing: fall back to the default browser
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
		select {}
	}
	defer w.Destroy()
	w.Navigate(url)
	w.Run()
	os.Exit(0)
}

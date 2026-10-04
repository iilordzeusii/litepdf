package main

import (
	"bytes"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"embed"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math/big"
	"mime"
	"net"
	"net/http"
	"os"
	"path"
	"strings"
	"time"

	"github.com/digitorus/pdf"
	"github.com/digitorus/pdfsign/sign"
	pkcs12 "software.sslmate.com/src/go-pkcs12"
)

//go:embed all:dist
var distFS embed.FS

func serveAsset(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(path.Clean("/"+r.URL.Path), "/")
	if p == "" {
		p = "index.html"
	}
	data, err := fs.ReadFile(distFS, "dist/"+p+".gz")
	if err != nil {
		http.NotFound(w, r)
		return
	}
	ct := mime.TypeByExtension(path.Ext(p))
	switch path.Ext(p) {
	case ".wasm":
		ct = "application/wasm"
	case ".js":
		ct = "text/javascript"
	case ".traineddata":
		ct = "application/octet-stream"
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Content-Encoding", "gzip")
	w.Header().Set("Cache-Control", "no-cache")
	w.Write(data)
}

func newSelfSigned(name string) (crypto.Signer, *x509.Certificate, error) {
	if name == "" {
		name = "LitePDF Test Signer"
	}
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, err
	}
	tpl := &x509.Certificate{SerialNumber: big.NewInt(time.Now().UnixNano()), Subject: pkix.Name{CommonName: name},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().AddDate(2, 0, 0),
		KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageContentCommitment, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageEmailProtection}}
	der, err := x509.CreateCertificate(rand.Reader, tpl, tpl, &key.PublicKey, key)
	if err != nil {
		return nil, nil, err
	}
	c, err := x509.ParseCertificate(der)
	return key, c, err
}

func signHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	if err := r.ParseMultipartForm(512 << 20); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	pf, _, err := r.FormFile("pdf")
	if err != nil {
		http.Error(w, "missing pdf", 400)
		return
	}
	pdfBytes, _ := io.ReadAll(pf)
	var signer crypto.Signer
	var cert *x509.Certificate
	var chain [][]*x509.Certificate
	if r.FormValue("gen") == "1" {
		signer, cert, err = newSelfSigned(r.FormValue("name"))
	} else {
		cf, _, e := r.FormFile("pfx")
		if e != nil {
			http.Error(w, "missing certificate file", 400)
			return
		}
		pfx, _ := io.ReadAll(cf)
		key, c, ca, e := pkcs12.DecodeChain(pfx, r.FormValue("password"))
		if e != nil {
			http.Error(w, "cannot read certificate (wrong password or unsupported file): "+e.Error(), 400)
			return
		}
		s, ok := key.(crypto.Signer)
		if !ok {
			http.Error(w, "certificate key type not supported for signing", 400)
			return
		}
		signer, cert = s, c
		if len(ca) > 0 {
			chain = [][]*x509.Certificate{append([]*x509.Certificate{c}, ca...)}
		}
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	name := r.FormValue("name")
	if name == "" {
		name = cert.Subject.CommonName
	}
	rd, err := pdf.NewReader(bytes.NewReader(pdfBytes), int64(len(pdfBytes)))
	if err != nil {
		http.Error(w, "cannot parse PDF for signing: "+err.Error(), 400)
		return
	}
	var out bytes.Buffer
	err = sign.Sign(bytes.NewReader(pdfBytes), &out, rd, int64(len(pdfBytes)), sign.SignData{
		Signature: sign.SignDataSignature{CertType: sign.ApprovalSignature, DocMDPPerm: sign.AllowFillingExistingFormFieldsAndSignaturesPerms,
			Info: sign.SignDataSignatureInfo{Name: name, Location: r.FormValue("location"), Reason: r.FormValue("reason"), Date: time.Now()}},
		Signer: signer, DigestAlgorithm: crypto.SHA256, Certificate: cert, CertificateChains: chain,
	})
	if err != nil {
		http.Error(w, "signing failed: "+err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/pdf")
	w.Write(out.Bytes())
}

// aiHandler forwards one AI request to Gemini or OpenRouter. It avoids browser CORS limits;
// the API key only travels from this app's page to localhost and then to the provider.
func aiHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "POST only", 405)
		return
	}
	key := r.Header.Get("X-Api-Key")
	body, _ := io.ReadAll(io.LimitReader(r.Body, 64<<20))
	var url string
	req := func(u string) (*http.Request, error) { return http.NewRequestWithContext(r.Context(), "POST", u, bytes.NewReader(body)) }
	base := os.Getenv("LITEPDF_AI_BASE") // tests only
	var hr *http.Request
	var err error
	switch r.URL.Query().Get("p") {
	case "gemini":
		m := r.URL.Query().Get("model")
		if strings.ContainsAny(m, "/?# ") {
			http.Error(w, "bad model id", 400)
			return
		}
		if base == "" {
			base = "https://generativelanguage.googleapis.com"
		}
		url = base + "/v1beta/models/" + m + ":generateContent"
		hr, err = req(url)
		if err == nil {
			hr.Header.Set("x-goog-api-key", key)
		}
	case "openrouter":
		if base == "" {
			base = "https://openrouter.ai"
		}
		url = base + "/api/v1/chat/completions"
		hr, err = req(url)
		if err == nil {
			hr.Header.Set("Authorization", "Bearer "+key)
		}
	default:
		http.Error(w, "unknown provider", 400)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	hr.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 180 * time.Second}).Do(hr)
	if err != nil {
		http.Error(w, "request failed: "+err.Error(), 502)
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--selftest-listen" { // headless mode for tests
		serve(os.Args[2])
		return
	}
	if len(os.Args) > 2 && os.Args[1] == "--makecert" {
		key, c, err := newSelfSigned("LitePDF Test Signer")
		if err != nil {
			log.Fatal(err)
		}
		pfx, err := pkcs12.Modern.Encode(key, c, nil, "test")
		if err != nil {
			log.Fatal(err)
		}
		os.WriteFile(os.Args[2], pfx, 0600)
		fmt.Println("wrote", os.Args[2], "(password: test)")
		return
	}
	addr := "127.0.0.1:47821"
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		ln, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Fatal(err)
		}
	}
	go serveOn(ln)
	showWindow("http://" + ln.Addr().String() + "/")
}

func mux() *http.ServeMux {
	m := http.NewServeMux()
	m.HandleFunc("/api/sign", signHandler)
	m.HandleFunc("/api/ai", aiHandler)
	m.HandleFunc("/", serveAsset)
	return m
}
func serveOn(ln net.Listener) { log.Fatal(http.Serve(ln, mux())) }
func serve(addr string)      { log.Fatal(http.ListenAndServe(addr, mux())) }

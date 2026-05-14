// Build test_geoip.mmdb from test_geoip.jsonl.
//
// Each line in the JSONL is one network entry. The "cidr" field becomes the
// MMDB network key; every other field becomes a string-typed record column.
//
// Usage:
//   go run build_test_mmdb.go
//
// Produces test_geoip.mmdb in the current directory. The output is the same
// shape (string-keyed columns) as IPInfo Lite, so corpus/ipinfo_geoip_enrichment.vrl
// runs against it unchanged with --mmdb-table ipinfo_lite=test_geoip.mmdb.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"

	"github.com/maxmind/mmdbwriter"
	"github.com/maxmind/mmdbwriter/mmdbtype"
)

func main() {
	srcPath := "test_geoip.jsonl"
	outPath := "test_geoip.mmdb"

	src, err := os.Open(srcPath)
	must(err)
	defer src.Close()

	writer, err := mmdbwriter.New(mmdbwriter.Options{
		DatabaseType: "test-geoip",
		RecordSize:   24,
	})
	must(err)

	scanner := bufio.NewScanner(src)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	lineNum := 0
	for scanner.Scan() {
		lineNum++
		raw := scanner.Bytes()
		if len(raw) == 0 {
			continue
		}
		var row map[string]string
		if err := json.Unmarshal(raw, &row); err != nil {
			fail("line %d: %v", lineNum, err)
		}
		cidrStr, ok := row["cidr"]
		if !ok || cidrStr == "" {
			fail("line %d: missing or empty 'cidr'", lineNum)
		}
		_, network, err := net.ParseCIDR(cidrStr)
		if err != nil {
			fail("line %d: bad cidr %q: %v", lineNum, cidrStr, err)
		}
		data := mmdbtype.Map{}
		for k, v := range row {
			if k == "cidr" {
				continue
			}
			data[mmdbtype.String(k)] = mmdbtype.String(v)
		}
		if err := writer.Insert(network, data); err != nil {
			fail("line %d: insert %s: %v", lineNum, cidrStr, err)
		}
	}
	must(scanner.Err())

	out, err := os.Create(outPath)
	must(err)
	defer out.Close()

	n, err := writer.WriteTo(out)
	must(err)

	fmt.Printf("wrote %s (%d bytes, %d networks)\n", outPath, n, lineNum)
}

func must(err error) {
	if err != nil {
		fail("%v", err)
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "build_test_mmdb: "+format+"\n", args...)
	os.Exit(1)
}

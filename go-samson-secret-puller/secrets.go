package samsonsecretpuller

import (
	"io/ioutil"
	"path/filepath"
	"strings"
)

// Secrets returns a map of secret names and values
func Secrets() (map[string]string, error) {
	s, err := readSecrets("/secrets")
	return s, err
}

func readSecrets(d string) (map[string]string, error) {
	s := make(map[string]string)
	files, err := ioutil.ReadDir(d)

	if err != nil {
		return s, err
	}

	for _, file := range files {
		n := file.Name()
		if strings.HasPrefix(n, ".") {
			continue
		}
		data, err := ioutil.ReadFile(filepath.Join(d, n))
		if err != nil {
			return s, err
		}
		s[n] = strings.TrimSpace(string(data))
	}

	return s, err
}

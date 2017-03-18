package samsonsecretpuller

import (
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestReading(t *testing.T) {
	s := []byte("agent\n")
	dir, err := ioutil.TempDir("", "secrets")
	if err != nil {
		log.Fatal(err)
	}
	defer os.RemoveAll(dir)

	if err := ioutil.WriteFile(filepath.Join(dir, "hemmelig"), s, 0644); err != nil {
		log.Fatal(err)
	}

	if err := ioutil.WriteFile(filepath.Join(dir, ".done"), s, 0644); err != nil {
		log.Fatal(err)
	}

	expected := map[string]string{"hemmelig": "agent"}
	secrets, _ := readSecrets(dir)

	if !reflect.DeepEqual(secrets, expected) {
		t.Errorf("Expected %v, got %v", expected, secrets)
	}
}

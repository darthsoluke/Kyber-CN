package util

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

func LoadConfig(filename string, config interface{}) error {
	path := filename
	if !filepath.IsAbs(path) {
		baseDir := os.Getenv("KYBER_CONFIG_DIR")
		if baseDir == "" {
			baseDir = "/srv/kyber-api/config"
		}

		path = filepath.Join(baseDir, filename)
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("%s: %w", path, err)
	}

	file, err := os.Open(path)
	if err != nil {
		return err
	}

	defer file.Close()

	if err := yaml.NewDecoder(file).Decode(config); err != nil {
		return err
	}

	return nil
}

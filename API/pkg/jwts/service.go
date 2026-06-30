package jwts

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/golang-jwt/jwt/v5"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
)

type Service struct {
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
	keyID      string
	mu         sync.RWMutex
}

func NewService() (*Service, error) {
	service := &Service{}

	privateKeyPath := os.Getenv("JWT_PRIVATE_KEY_PATH")
	publicKeyPath := os.Getenv("JWT_PUBLIC_KEY_PATH")

	if privateKeyPath != "" && publicKeyPath != "" {
		if err := service.loadKeysFromFiles(privateKeyPath, publicKeyPath); err != nil {
			return nil, fmt.Errorf("failed to load keys from files: %w", err)
		}
		logger.L().Info("JWT keys loaded from files")
	} else {
		if err := service.generateKeys(); err != nil {
			return nil, fmt.Errorf("failed to generate keys: %w", err)
		}
		logger.L().Info("JWT keys generated")
	}

	keyID, err := ComputeKeyID(service.publicKey)
	if err != nil {
		return nil, fmt.Errorf("failed to compute key ID: %w", err)
	}

	service.keyID = keyID

	return service, nil
}

func (s *Service) loadKeysFromFiles(privateKeyPath, publicKeyPath string) error {
	privateKeyPath = resolveKeyPath(privateKeyPath)
	publicKeyPath = resolveKeyPath(publicKeyPath)

	privPEM, err := os.ReadFile(privateKeyPath)
	if err != nil {
		return fmt.Errorf("read private key: %w", err)
	}

	block, _ := pem.Decode(privPEM)
	if block == nil || !strings.Contains(block.Type, "PRIVATE") {
		return fmt.Errorf("invalid private key PEM")
	}

	privKeyIfc, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		privKeyIfc, err = x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return fmt.Errorf("parse private key: %w", err)
		}
	}

	privKey, ok := privKeyIfc.(*rsa.PrivateKey)
	if !ok {
		return fmt.Errorf("private key is not RSA")
	}

	pubPEM, err := os.ReadFile(publicKeyPath)
	if err != nil {
		return fmt.Errorf("read public key: %w", err)
	}

	block, _ = pem.Decode(pubPEM)
	if block == nil || !strings.Contains(block.Type, "PUBLIC") {
		return fmt.Errorf("invalid public key PEM")
	}

	pubIfc, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return fmt.Errorf("parse public key: %w", err)
	}

	pubKey, ok := pubIfc.(*rsa.PublicKey)
	if !ok {
		return fmt.Errorf("public key is not RSA")
	}

	s.privateKey = privKey
	s.publicKey = pubKey

	return nil
}

func resolveKeyPath(path string) string {
	if filepath.IsAbs(path) {
		return path
	}

	baseDir := os.Getenv("JWT_KEY_DIR")
	if baseDir == "" {
		baseDir = "/srv/kyber-api/jwt"
	}

	return filepath.Join(baseDir, path)
}

func (s *Service) generateKeys() error {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("generate RSA key: %w", err)
	}

	s.privateKey = privateKey
	s.publicKey = &privateKey.PublicKey

	return nil
}

func (s *Service) SignToken(claims jwt.Claims) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = s.keyID

	signed, err := token.SignedString(s.privateKey)
	if err != nil {
		return "", fmt.Errorf("sign token: %w", err)
	}

	return signed, nil
}

func (s *Service) GetPublicKey() *rsa.PublicKey {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.publicKey
}

func (s *Service) GetKeyID() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.keyID
}

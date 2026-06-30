package api

import (
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base32"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/db"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/ArmchairDevelopers/Kyber/API/pkg/models"
	"github.com/golang-jwt/jwt/v5"
	"go.uber.org/zap"
)

type DockerAuthState struct {
	store      *db.Store
	privateKey *rsa.PrivateKey
	keyID      string
}

type Claims struct {
	Access []map[string]interface{} `json:"access"`
	Aud    string                   `json:"aud"`
	Exp    int64                    `json:"exp"`
	Iat    int64                    `json:"iat"`
	Iss    string                   `json:"iss"`
	Jti    string                   `json:"jti"`
	Nbf    int64                    `json:"nbf"`
	Sub    string                   `json:"sub"`
}

func NewDockerAuthState(store *db.Store) (*DockerAuthState, error) {
	pubPEMPath := os.Getenv("DOCKER_CRT_PATH")
	if pubPEMPath == "" {
		return nil, nil
	}

	path := resolveDockerKeyPath(pubPEMPath)
	pubPEM, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read public key: %w", err)
	}

	block, _ := pem.Decode(pubPEM)
	if block == nil || !strings.Contains(block.Type, "PUBLIC") {
		return nil, fmt.Errorf("invalid public key PEM")
	}

	pubIfc, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}

	pubKey, ok := pubIfc.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public key is not RSA")
	}

	keyID, err := computeKeyID(pubKey)
	if err != nil {
		return nil, fmt.Errorf("compute key ID: %w", err)
	}

	privPEMPath := os.Getenv("DOCKER_KEY_PATH")
	if privPEMPath == "" {
		return nil, fmt.Errorf("DOCKER_KEY_PATH env var required when DOCKER_CRT_PATH is set")
	}

	path = resolveDockerKeyPath(privPEMPath)
	privPEM, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read private key: %w", err)
	}

	block, _ = pem.Decode(privPEM)
	if block == nil || !strings.Contains(block.Type, "PRIVATE") {
		return nil, fmt.Errorf("invalid private key PEM")
	}

	privKeyIfc, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse private key: %w", err)
	}

	privKey, ok := privKeyIfc.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("private key is not RSA")
	}

	return &DockerAuthState{
		store:      store,
		privateKey: privKey,
		keyID:      keyID,
	}, nil
}

func resolveDockerKeyPath(path string) string {
	if filepath.IsAbs(path) {
		return path
	}

	baseDir := os.Getenv("DOCKER_KEY_DIR")
	if baseDir == "" {
		baseDir = "/srv/kyber-api/docker"
	}

	return filepath.Join(baseDir, path)
}

func computeKeyID(pub *rsa.PublicKey) (string, error) {
	derBytes, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}

	hash := sha256.Sum256(derBytes)
	trunc := hash[:30]
	enc := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(trunc)
	parts := make([]string, 0, len(enc)/4)
	for i := 0; i < len(enc); i += 4 {
		end := i + 4
		if end > len(enc) {
			end = len(enc)
		}
		parts = append(parts, enc[i:end])
	}
	return strings.Join(parts, ":"), nil
}

func parseScope(scope string, pushAllowed bool) []map[string]interface{} {
	parts := strings.Split(scope, ":")
	if len(parts) != 3 {
		return nil
	}
	resourceType, name, actions := parts[0], parts[1], parts[2]
	var out []map[string]interface{}
	for _, act := range strings.Split(actions, ",") {
		switch act {
		case "push":
			if pushAllowed {
				out = append(out, map[string]interface{}{
					"type":    resourceType,
					"name":    name,
					"actions": []string{"push"},
				})
			}
		case "pull":
			out = append(out, map[string]interface{}{
				"type":    resourceType,
				"name":    name,
				"actions": []string{"pull"},
			})
		}
	}
	return out
}

func (s *DockerAuthState) canPush(r *http.Request) bool {
	user, pass, ok := r.BasicAuth()
	if !ok || user != "kyber" {
		return false
	}

	ctx := r.Context()
	account, err := s.store.Users.GetByToken(ctx, pass)
	if err != nil {
		logger.L().Error("docker auth: db error", zap.Error(err))
		return false
	}

	if account == nil {
		return false
	}

	return account.Entitled(models.EntitlementDockerPush)
}

func (s *DockerAuthState) AuthHandler(w http.ResponseWriter, r *http.Request) {
	scopeParam := r.URL.Query().Get("scope")
	var access []map[string]interface{}
	if scopeParam != "" {
		access = parseScope(scopeParam, s.canPush(r))
	}

	now := time.Now().Unix()
	claims := Claims{
		Access: access,
		Aud:    "registry.kyber.gg",
		Exp:    now + 3600,
		Iat:    now,
		Iss:    "api.prod.kyber.gg",
		Jti:    "",
		Nbf:    now - 60,
		Sub:    "",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"access": claims.Access,
		"aud":    claims.Aud,
		"exp":    claims.Exp,
		"iat":    claims.Iat,
		"iss":    claims.Iss,
		"jti":    claims.Jti,
		"nbf":    claims.Nbf,
		"sub":    claims.Sub,
	})
	token.Header["kid"] = s.keyID

	signed, err := token.SignedString(s.privateKey)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	resp := map[string]string{"token": signed}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

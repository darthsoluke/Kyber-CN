package ea

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

type JwtClaims struct {
	Nexus EAJwtNexusClaims `json:"nexus"`
	jwt.RegisteredClaims
}

type JsonWebKey struct {
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Kty string `json:"kty"`
}

type JwtUserInformationClaims struct {
	Cty string `json:"cty"`
	Lan string `json:"lan"`
	Sta string `json:"sta"`
}

type JwtUserPersonaInformationClaims struct {
	ID  uint64 `json:"id"`
	Ns  string `json:"ns"`
	Dis string `json:"dis"`
	Nic string `json:"nic"`
}

type EAJwtNexusClaims struct {
	Pid  string                            `json:"pid"`
	Uid  string                            `json:"uid"`
	Psid uint64                            `json:"psid"`
	Dvid string                            `json:"dvid"`
	Uif  JwtUserInformationClaims          `json:"uif"`
	Psif []JwtUserPersonaInformationClaims `json:"psif"`
}

func (c *EAJwtNexusClaims) PersonaInfo() *JwtUserPersonaInformationClaims {
	for i := range c.Psif {
		if c.Psif[i].Ns == "cem_ea_id" {
			return &c.Psif[i]
		}
	}

	return nil
}

type JsonWebKeySet struct {
	Keys []JsonWebKey `json:"keys"`
}

func LoadJwks() (map[string]*rsa.PublicKey, error) {
	endpoint := os.Getenv("EA_JWKS_ENDPOINT")
	if endpoint == "" {
		return nil, errors.New("EA_JWKS_ENDPOINT environment variable is not set")
	}

	resp, err := http.Get(endpoint)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch EA JWKS: %w", err)
	}

	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to fetch EA JWKS: %s", resp.Status)
	}

	defer resp.Body.Close()

	var jwks JsonWebKeySet
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("failed to decode EA JWKS: %w", err)
	}

	out := make(map[string]*rsa.PublicKey, len(jwks.Keys))
	for _, key := range jwks.Keys {
		nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
		if err != nil {
			return nil, fmt.Errorf("invalid N for kid %q: %w", key.Kid, err)
		}
		eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
		if err != nil {
			return nil, fmt.Errorf("invalid E for kid %q: %w", key.Kid, err)
		}
		n := new(big.Int).SetBytes(nBytes)
		e := int(new(big.Int).SetBytes(eBytes).Int64())

		out[key.Kid] = &rsa.PublicKey{N: n, E: e}
	}

	return out, nil
}

func ValidateToken(jwks map[string]*rsa.PublicKey, tokenStr string) (*EAJwtNexusClaims, error) {
	parts := strings.Split(tokenStr, ".")
	if len(parts) < 2 {
		return nil, errors.New("invalid token format")
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("failed to decode token header: %w", err)
	}
	var header struct {
		Kid string `json:"kid"`
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return nil, fmt.Errorf("failed to unmarshal token header: %w", err)
	}
	kid := header.Kid

	key, ok := jwks[kid]
	if !ok {
		return nil, fmt.Errorf("invalid key ID in EA token: %s", kid)
	}

	var claims JwtClaims
	parsedToken, err := jwt.ParseWithClaims(tokenStr, &claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return key, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to validate JWT: %w", err)
	}

	if !parsedToken.Valid {
		return nil, errors.New("invalid EA token")
	}

	return &claims.Nexus, nil
}

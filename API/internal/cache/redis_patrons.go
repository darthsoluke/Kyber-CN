package cache

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/ArmchairDevelopers/Kyber/API/pkg/logger"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const patronListKeyPrefix = "patron_list"

type PatronsCache struct {
	rdb *redis.Client
	ttl time.Duration
}

func NewPatronsCache(rdb *redis.Client, ttl time.Duration) *PatronsCache {
	if ttl <= 0 {
		ttl = defaultTTL
	}
	return &PatronsCache{rdb: rdb, ttl: ttl}
}

func (c *PatronsCache) Get(ctx context.Context) (*[]string, error) {
	if c == nil || c.rdb == nil {
		return nil, nil
	}

	data, err := c.rdb.Get(ctx, patronListKeyPrefix).Bytes()

	if errors.Is(err, redis.Nil) {
		return nil, nil
	}

	if err != nil {
		logger.L().Error("redis GET error", zap.Error(err))
		return nil, err
	}

	var m []string
	if err := json.Unmarshal(data, &m); err != nil {
		logger.L().Error("json unmarshal error", zap.Error(err))
		return nil, err
	}

	return &m, nil
}

func (c *PatronsCache) Set(ctx context.Context, m *[]string) error {
	if c == nil || c.rdb == nil {
		return nil
	}

	data, err := json.Marshal(m)
	if err != nil {
		logger.L().Error("json marshal error", zap.Error(err))
		return err
	}

	if err := c.rdb.Set(ctx, patronListKeyPrefix, data, c.ttl).Err(); err != nil {
		logger.L().Error("redis SET error", zap.Error(err))
		return err
	}

	return nil
}
